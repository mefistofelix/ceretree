package main

/*
#include <stdlib.h>
#include "ceretree_grammars.h"
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"strings"
	"time"
	"unsafe"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

const version = "0.1.0"

var supported_languages = []string{
	"bash",
	"batch",
	"c",
	"cpp",
	"go",
	"javascript",
	"lua",
	"php",
	"powershell",
	"python",
	"rust",
	"tsx",
	"typescript",
}

type rpc_request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

type rpc_response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *rpc_error_body `json:"error,omitempty"`
}

type rpc_error_body struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type rpc_handler func(*runtime_context, json.RawMessage) (any, error)

type runtime_context struct {
	executable_path string
	cache_dir       string
	state_path      string
}

type cache_state struct {
	Roots []string `json:"roots"`
}

type roots_params struct {
	Paths []string `json:"paths"`
}

type query_params struct {
	Language string          `json:"language"`
	Query    string          `json:"query"`
	Roots    []string        `json:"roots"`
	Include  json.RawMessage `json:"include"`
	Exclude  json.RawMessage `json:"exclude"`
}

type file_match struct {
	Path     string          `json:"path"`
	Root     string          `json:"root"`
	Relative string          `json:"relative"`
	Captures []capture_match `json:"captures"`
}

type capture_match struct {
	Name      string     `json:"name"`
	Kind      string     `json:"kind"`
	Text      string     `json:"text"`
	StartByte uint       `json:"start_byte"`
	EndByte   uint       `json:"end_byte"`
	Start     point_json `json:"start"`
	End       point_json `json:"end"`
}

type point_json struct {
	Row    uint `json:"row"`
	Column uint `json:"column"`
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	request_text, err := parse_cli_request(args)
	if err != nil {
		return write_fatal(err)
	}

	context, err := new_runtime_context()
	if err != nil {
		return write_fatal(err)
	}

	request, response := decode_request([]byte(request_text))
	if response == nil {
		result, call_err := dispatch(context, request)
		response = build_response(request.ID, result, call_err)
	}

	if err := write_json(response); err != nil {
		return write_fatal(err)
	}

	return 0
}

func parse_cli_request(args []string) (string, error) {
	if len(args) == 0 {
		stdin, err := io.ReadAll(os.Stdin)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(string(stdin)) == "" {
			return "", errors.New("missing JSON-RPC request argument or stdin payload")
		}
		return string(stdin), nil
	}

	if args[0] == "-server" || args[0] == "--server" {
		return "", errors.New("server mode is not implemented yet in this slice")
	}

	return strings.Join(args, " "), nil
}

func new_runtime_context() (*runtime_context, error) {
	executable_path, err := os.Executable()
	if err != nil {
		return nil, err
	}

	cache_dir := filepath.Join(filepath.Dir(executable_path), ".ceretree-cache")
	if err := os.MkdirAll(cache_dir, 0o755); err != nil {
		return nil, err
	}

	return &runtime_context{
		executable_path: executable_path,
		cache_dir:       cache_dir,
		state_path:      filepath.Join(cache_dir, "state.json"),
	}, nil
}

func decode_request(data []byte) (*rpc_request, *rpc_response) {
	var request rpc_request
	if err := json.Unmarshal(data, &request); err != nil {
		return nil, &rpc_response{
			JSONRPC: "2.0",
			Error: &rpc_error_body{
				Code:    -32700,
				Message: fmt.Sprintf("invalid JSON: %v", err),
			},
		}
	}

	if request.JSONRPC != "2.0" {
		return nil, &rpc_response{
			JSONRPC: "2.0",
			ID:      request.ID,
			Error: &rpc_error_body{
				Code:    -32600,
				Message: "jsonrpc must be 2.0",
			},
		}
	}

	if strings.TrimSpace(request.Method) == "" {
		return nil, &rpc_response{
			JSONRPC: "2.0",
			ID:      request.ID,
			Error: &rpc_error_body{
				Code:    -32600,
				Message: "method is required",
			},
		}
	}

	return &request, nil
}

func dispatch(context *runtime_context, request *rpc_request) (any, error) {
	handlers := map[string]rpc_handler{
		"system.describe": handle_system_describe,
		"roots.list":      handle_roots_list,
		"roots.add":       handle_roots_add,
		"roots.remove":    handle_roots_remove,
		"query":           handle_query,
	}

	handler, ok := handlers[request.Method]
	if !ok {
		return nil, fmt.Errorf("method not found: %s", request.Method)
	}

	return handler(context, request.Params)
}

func build_response(id json.RawMessage, result any, err error) *rpc_response {
	if err == nil {
		return &rpc_response{
			JSONRPC: "2.0",
			ID:      id,
			Result:  result,
		}
	}

	code := -32000
	message := err.Error()

	switch {
	case strings.HasPrefix(message, "method not found:"):
		code = -32601
	case strings.HasPrefix(message, "invalid params:"):
		code = -32602
	}

	return &rpc_response{
		JSONRPC: "2.0",
		ID:      id,
		Error: &rpc_error_body{
			Code:    code,
			Message: message,
		},
	}
}

func handle_system_describe(context *runtime_context, _ json.RawMessage) (any, error) {
	return map[string]any{
		"name":            "ceretree",
		"version":         version,
		"os":              runtime.GOOS,
		"arch":            runtime.GOARCH,
		"executable_path": context.executable_path,
		"cache_dir":       context.cache_dir,
		"languages":       supported_languages,
		"server_mode": map[string]any{
			"implemented": false,
		},
		"methods": []string{
			"system.describe",
			"roots.list",
			"roots.add",
			"roots.remove",
			"query",
		},
	}, nil
}

func handle_roots_list(context *runtime_context, _ json.RawMessage) (any, error) {
	state, err := load_state(context)
	if err != nil {
		return nil, err
	}

	return map[string]any{
		"roots": state.Roots,
	}, nil
}

func handle_roots_add(context *runtime_context, params json.RawMessage) (any, error) {
	parsed, err := decode_roots_params(params)
	if err != nil {
		return nil, err
	}

	state, err := load_state(context)
	if err != nil {
		return nil, err
	}

	for _, path := range parsed.Paths {
		root, err := normalize_root(path)
		if err != nil {
			return nil, err
		}
		if !slices.Contains(state.Roots, root) {
			state.Roots = append(state.Roots, root)
		}
	}

	slices.Sort(state.Roots)
	if err := save_state(context, state); err != nil {
		return nil, err
	}

	return map[string]any{
		"roots": state.Roots,
	}, nil
}

func handle_roots_remove(context *runtime_context, params json.RawMessage) (any, error) {
	parsed, err := decode_roots_params(params)
	if err != nil {
		return nil, err
	}

	state, err := load_state(context)
	if err != nil {
		return nil, err
	}

	remove_set := map[string]struct{}{}
	for _, path := range parsed.Paths {
		root, err := normalize_root(path)
		if err != nil {
			return nil, err
		}
		remove_set[root] = struct{}{}
	}

	kept := state.Roots[:0]
	for _, root := range state.Roots {
		if _, remove := remove_set[root]; !remove {
			kept = append(kept, root)
		}
	}
	state.Roots = kept

	if err := save_state(context, state); err != nil {
		return nil, err
	}

	return map[string]any{
		"roots": state.Roots,
	}, nil
}

func handle_query(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed query_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("query params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}
	if strings.TrimSpace(parsed.Query) == "" {
		return nil, invalid_params("query is required")
	}

	language, err := linked_language(parsed.Language)
	if err != nil {
		return nil, err
	}

	query, query_err := tree_sitter.NewQuery(language, parsed.Query)
	if query_err != nil {
		return nil, fmt.Errorf(
			"tree-sitter query error at row %d column %d: %s",
			query_err.Row,
			query_err.Column,
			query_err.Message,
		)
	}
	defer query.Close()

	parser := tree_sitter.NewParser()
	defer parser.Close()

	if err := parser.SetLanguage(language); err != nil {
		return nil, err
	}

	cursor := tree_sitter.NewQueryCursor()
	defer cursor.Close()

	roots, err := resolve_roots(context, parsed.Roots)
	if err != nil {
		return nil, err
	}

	include_patterns, err := decode_patterns(parsed.Include)
	if err != nil {
		return nil, err
	}
	exclude_patterns, err := decode_patterns(parsed.Exclude)
	if err != nil {
		return nil, err
	}

	started := time.Now().UTC()
	var matches []file_match
	var files_scanned int

	for _, root := range roots {
		root_matches, scanned, err := query_root(root, include_patterns, exclude_patterns, parser, query, cursor)
		if err != nil {
			return nil, err
		}
		matches = append(matches, root_matches...)
		files_scanned += scanned
	}

	_ = touch_cache_file(filepath.Join(context.cache_dir, "last-query.json"), map[string]any{
		"timestamp":     started.Format(time.RFC3339Nano),
		"language":      parsed.Language,
		"files_scanned": files_scanned,
		"files_matched": len(matches),
	})

	return map[string]any{
		"roots": roots,
		"summary": map[string]any{
			"language":      parsed.Language,
			"files_scanned": files_scanned,
			"files_matched": len(matches),
			"started_at":    started.Format(time.RFC3339Nano),
			"duration_ms":   time.Since(started).Milliseconds(),
		},
		"matches": matches,
	}, nil
}

func linked_language(name string) (*tree_sitter.Language, error) {
	if !slices.Contains(supported_languages, name) {
		return nil, invalid_params(fmt.Sprintf("unsupported language: %s", name))
	}

	name_c := C.CString(name)
	defer C.free(unsafe.Pointer(name_c))

	pointer := C.ceretree_language(name_c)
	if pointer == nil {
		return nil, fmt.Errorf("compiled grammar not available for language: %s", name)
	}

	return tree_sitter.NewLanguage(unsafe.Pointer(pointer)), nil
}

func decode_roots_params(params json.RawMessage) (*roots_params, error) {
	var parsed roots_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("roots params must be an object")
	}
	if len(parsed.Paths) == 0 {
		return nil, invalid_params("paths must contain at least one item")
	}
	return &parsed, nil
}

func load_state(context *runtime_context) (*cache_state, error) {
	data, err := os.ReadFile(context.state_path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return &cache_state{}, nil
		}
		return nil, err
	}

	var state cache_state
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("invalid cache state: %w", err)
	}

	slices.Sort(state.Roots)
	state.Roots = slices.Compact(state.Roots)
	return &state, nil
}

func save_state(context *runtime_context, state *cache_state) error {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(context.state_path, data, 0o644)
}

func resolve_roots(context *runtime_context, explicit []string) ([]string, error) {
	if len(explicit) > 0 {
		roots := make([]string, 0, len(explicit))
		for _, path := range explicit {
			root, err := normalize_root(path)
			if err != nil {
				return nil, err
			}
			roots = append(roots, root)
		}
		slices.Sort(roots)
		return slices.Compact(roots), nil
	}

	state, err := load_state(context)
	if err != nil {
		return nil, err
	}
	if len(state.Roots) == 0 {
		return nil, invalid_params("no roots configured; use roots.add or pass roots in query params")
	}
	return state.Roots, nil
}

func normalize_root(path string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", invalid_params("root paths cannot be empty")
	}

	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}

	info, err := os.Stat(absolute)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", invalid_params(fmt.Sprintf("root is not a directory: %s", absolute))
	}

	return filepath.Clean(absolute), nil
}

func decode_patterns(raw json.RawMessage) ([]string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return nil, nil
	}

	var single string
	if err := json.Unmarshal(raw, &single); err == nil {
		if strings.TrimSpace(single) == "" {
			return nil, nil
		}
		return []string{filepath.ToSlash(single)}, nil
	}

	var many []string
	if err := json.Unmarshal(raw, &many); err == nil {
		patterns := make([]string, 0, len(many))
		for _, pattern := range many {
			if strings.TrimSpace(pattern) == "" {
				continue
			}
			patterns = append(patterns, filepath.ToSlash(pattern))
		}
		return patterns, nil
	}

	return nil, invalid_params("include/exclude must be a string, an array of strings, or null")
}

func query_root(
	root string,
	include_patterns []string,
	exclude_patterns []string,
	parser *tree_sitter.Parser,
	query *tree_sitter.Query,
	cursor *tree_sitter.QueryCursor,
) ([]file_match, int, error) {
	var matches []file_match
	var files_scanned int

	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walk_err error) error {
		if walk_err != nil {
			return walk_err
		}
		if entry.IsDir() {
			return nil
		}

		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)

		if !matches_any(relative, include_patterns, true) || matches_any(relative, exclude_patterns, false) {
			return nil
		}

		files_scanned++
		file_matches, err := query_file(path, root, relative, parser, query, cursor)
		if err != nil {
			return err
		}
		if len(file_matches.Captures) > 0 {
			matches = append(matches, file_matches)
		}
		return nil
	})

	return matches, files_scanned, err
}

func query_file(
	path string,
	root string,
	relative string,
	parser *tree_sitter.Parser,
	query *tree_sitter.Query,
	cursor *tree_sitter.QueryCursor,
) (file_match, error) {
	source, err := os.ReadFile(path)
	if err != nil {
		return file_match{}, err
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		return file_match{}, fmt.Errorf("tree-sitter parse failed for %s", path)
	}
	defer tree.Close()

	root_node := tree.RootNode()
	query_matches := cursor.Matches(query, root_node, source)
	var captures []capture_match

	for match := query_matches.Next(); match != nil; match = query_matches.Next() {
		if !match.SatisfiesTextPredicate(query, nil, nil, source) {
			continue
		}
		for _, capture := range match.Captures {
			node := capture.Node
			captures = append(captures, capture_match{
				Name:      capture_name(query, uint(capture.Index)),
				Kind:      node.Kind(),
				Text:      node.Utf8Text(source),
				StartByte: node.StartByte(),
				EndByte:   node.EndByte(),
				Start:     point_from_tree(node.StartPosition()),
				End:       point_from_tree(node.EndPosition()),
			})
		}
	}

	return file_match{
		Path:     path,
		Root:     root,
		Relative: relative,
		Captures: captures,
	}, nil
}

func capture_name(query *tree_sitter.Query, index uint) string {
	names := query.CaptureNames()
	if int(index) >= len(names) {
		return fmt.Sprintf("#%d", index)
	}
	return names[index]
}

func point_from_tree(point tree_sitter.Point) point_json {
	return point_json{
		Row:    point.Row,
		Column: point.Column,
	}
}

func matches_any(path string, patterns []string, default_when_empty bool) bool {
	if len(patterns) == 0 {
		return default_when_empty
	}

	for _, pattern := range patterns {
		if doublestar_match(path, pattern) {
			return true
		}
	}
	return false
}

func doublestar_match(path string, pattern string) bool {
	regex := doublestar_regex(filepath.ToSlash(pattern))
	return regex.MatchString(filepath.ToSlash(path))
}

func doublestar_regex(pattern string) *regexp.Regexp {
	var builder strings.Builder
	builder.WriteString("^")

	for index := 0; index < len(pattern); {
		switch pattern[index] {
		case '*':
			if index+1 < len(pattern) && pattern[index+1] == '*' {
				builder.WriteString(".*")
				index += 2
				continue
			}
			builder.WriteString("[^/]*")
		case '?':
			builder.WriteString("[^/]")
		case '.', '+', '(', ')', '[', ']', '{', '}', '^', '$', '|', '\\':
			builder.WriteByte('\\')
			builder.WriteByte(pattern[index])
		default:
			builder.WriteByte(pattern[index])
		}
		index++
	}

	builder.WriteString("$")
	return regexp.MustCompile(builder.String())
}

func touch_cache_file(path string, payload any) error {
	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

func non_nil_params(params json.RawMessage) []byte {
	if len(params) == 0 {
		return []byte("{}")
	}
	return params
}

func invalid_params(message string) error {
	return fmt.Errorf("invalid params: %s", message)
}

func write_json(value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	_, err = os.Stdout.Write(append(data, '\n'))
	return err
}

func write_fatal(err error) int {
	response := &rpc_response{
		JSONRPC: "2.0",
		Error: &rpc_error_body{
			Code:    -32000,
			Message: err.Error(),
		},
	}
	_ = write_json(response)
	return 1
}
