package main

/*
#include <stdlib.h>
#include "ceretree_grammars.h"
*/
import "C"

import (
	"bytes"
	"crypto/sha1"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
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

const version = "0.7.0"

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
	process_id      int
	server_mode     bool
	server_target   string
	started_at      time.Time
}

type cache_state struct {
	Roots []string `json:"roots"`
}

type analysis_cache_entry struct {
	Version    int               `json:"version"`
	Language   string            `json:"language"`
	Path       string            `json:"path"`
	Size       int64             `json:"size"`
	ModifiedAt string            `json:"modified_at"`
	Symbols    []symbol_overview `json:"symbols"`
	Calls      []call_match      `json:"calls"`
	References []reference_match `json:"references"`
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
	Limit    int             `json:"limit"`
	Offset   int             `json:"offset"`
}

type symbols_overview_params struct {
	Language   string          `json:"language"`
	Roots      []string        `json:"roots"`
	Include    json.RawMessage `json:"include"`
	Exclude    json.RawMessage `json:"exclude"`
	MaxSymbols int             `json:"max_symbols"`
	Limit      int             `json:"limit"`
	Offset     int             `json:"offset"`
}

type symbols_find_params struct {
	Language   string          `json:"language"`
	Name       string          `json:"name"`
	Kinds      []string        `json:"kinds"`
	Roots      []string        `json:"roots"`
	Include    json.RawMessage `json:"include"`
	Exclude    json.RawMessage `json:"exclude"`
	MatchMode  string          `json:"match_mode"`
	MaxSymbols int             `json:"max_symbols"`
	Limit      int             `json:"limit"`
	Offset     int             `json:"offset"`
}

type calls_find_params struct {
	Language  string          `json:"language"`
	Callee    string          `json:"callee"`
	Roots     []string        `json:"roots"`
	Include   json.RawMessage `json:"include"`
	Exclude   json.RawMessage `json:"exclude"`
	MatchMode string          `json:"match_mode"`
	MaxCalls  int             `json:"max_calls"`
	Limit     int             `json:"limit"`
	Offset    int             `json:"offset"`
}

type references_find_params struct {
	Language      string          `json:"language"`
	Name          string          `json:"name"`
	Kinds         []string        `json:"kinds"`
	Roots         []string        `json:"roots"`
	Include       json.RawMessage `json:"include"`
	Exclude       json.RawMessage `json:"exclude"`
	MatchMode     string          `json:"match_mode"`
	MaxReferences int             `json:"max_references"`
	Limit         int             `json:"limit"`
	Offset        int             `json:"offset"`
}

type query_common_params struct {
	Language  string          `json:"language"`
	Preset    string          `json:"preset"`
	Name      string          `json:"name"`
	Kinds     []string        `json:"kinds"`
	Roots     []string        `json:"roots"`
	Include   json.RawMessage `json:"include"`
	Exclude   json.RawMessage `json:"exclude"`
	MatchMode string          `json:"match_mode"`
	MaxItems  int             `json:"max_items"`
	Limit     int             `json:"limit"`
	Offset    int             `json:"offset"`
}

type context_at_params struct {
	Language string   `json:"language"`
	Path     string   `json:"path"`
	Roots    []string `json:"roots"`
	Row      int      `json:"row"`
	Column   int      `json:"column"`
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

type symbol_file struct {
	Path     string            `json:"path"`
	Root     string            `json:"root"`
	Relative string            `json:"relative"`
	Symbols  []symbol_overview `json:"symbols"`
}

type symbol_overview struct {
	Kind        string     `json:"kind"`
	GrammarKind string     `json:"grammar_kind"`
	Name        string     `json:"name"`
	Container   string     `json:"container,omitempty"`
	Signature   string     `json:"signature,omitempty"`
	StartByte   uint       `json:"start_byte"`
	EndByte     uint       `json:"end_byte"`
	Start       point_json `json:"start"`
	End         point_json `json:"end"`
}

type call_file struct {
	Path     string       `json:"path"`
	Root     string       `json:"root"`
	Relative string       `json:"relative"`
	Calls    []call_match `json:"calls"`
}

type call_match struct {
	Callee     string     `json:"callee"`
	Expression string     `json:"expression"`
	Kind       string     `json:"kind"`
	StartByte  uint       `json:"start_byte"`
	EndByte    uint       `json:"end_byte"`
	Start      point_json `json:"start"`
	End        point_json `json:"end"`
}

type point_json struct {
	Row    uint `json:"row"`
	Column uint `json:"column"`
}

type reference_file struct {
	Path       string            `json:"path"`
	Root       string            `json:"root"`
	Relative   string            `json:"relative"`
	References []reference_match `json:"references"`
}

type reference_match struct {
	Name       string     `json:"name"`
	Kind       string     `json:"kind"`
	Expression string     `json:"expression"`
	StartByte  uint       `json:"start_byte"`
	EndByte    uint       `json:"end_byte"`
	Start      point_json `json:"start"`
	End        point_json `json:"end"`
}

type node_context struct {
	Kind        string     `json:"kind"`
	GrammarKind string     `json:"grammar_kind"`
	Name        string     `json:"name,omitempty"`
	Signature   string     `json:"signature,omitempty"`
	StartByte   uint       `json:"start_byte"`
	EndByte     uint       `json:"end_byte"`
	Start       point_json `json:"start"`
	End         point_json `json:"end"`
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	request_text, server_target, err := parse_cli_mode(args)
	if err != nil {
		return write_fatal(err)
	}

	context, err := new_runtime_context(server_target != "", server_target)
	if err != nil {
		return write_fatal(err)
	}

	if server_target != "" {
		return serve_http(context)
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

func parse_cli_mode(args []string) (string, string, error) {
	if len(args) == 0 {
		stdin, err := io.ReadAll(os.Stdin)
		if err != nil {
			return "", "", err
		}
		stdin = strip_utf8_bom(stdin)
		if strings.TrimSpace(string(stdin)) == "" {
			return "", "", errors.New("missing JSON-RPC request argument or stdin payload")
		}
		return string(stdin), "", nil
	}

	if strings.HasPrefix(args[0], "--server=") {
		target := strings.TrimSpace(strings.TrimPrefix(args[0], "--server="))
		if target == "" {
			return "", "", errors.New("missing server target; use --server unix://path.sock or --server tcp://127.0.0.1:9000")
		}
		return "", target, nil
	}

	if args[0] == "-server" || args[0] == "--server" {
		if len(args) != 2 {
			return "", "", errors.New("server mode requires exactly one target; use --server unix://path.sock or --server tcp://127.0.0.1:9000")
		}
		if strings.TrimSpace(args[1]) == "" {
			return "", "", errors.New("missing server target; use --server unix://path.sock or --server tcp://127.0.0.1:9000")
		}
		return "", args[1], nil
	}

	return strings.Join(args, " "), "", nil
}

func new_runtime_context(server_mode bool, server_target string) (*runtime_context, error) {
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
		process_id:      os.Getpid(),
		server_mode:     server_mode,
		server_target:   server_target,
		started_at:      time.Now().UTC(),
	}, nil
}

func serve_http(context *runtime_context) int {
	network, address, err := decode_server_target(context.server_target)
	if err != nil {
		return write_fatal(err)
	}

	if network == "unix" {
		if err := os.MkdirAll(filepath.Dir(address), 0o755); err != nil {
			return write_fatal(err)
		}
		_ = os.Remove(address)
	}

	listener, err := net.Listen(network, address)
	if err != nil {
		return write_fatal(err)
	}
	defer listener.Close()
	if network == "unix" {
		defer os.Remove(address)
	}

	server := http.Server{
		Handler: http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
			serve_http_request(context, writer, request)
		}),
		ReadHeaderTimeout: 10 * time.Second,
	}

	if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return write_fatal(err)
	}

	return 0
}

func decode_server_target(target string) (string, string, error) {
	if strings.HasPrefix(target, "unix://") {
		address := strings.TrimSpace(strings.TrimPrefix(target, "unix://"))
		if address == "" {
			return "", "", invalid_params("unix server target must be unix://path.sock")
		}
		address = filepath.FromSlash(address)
		if !filepath.IsAbs(address) {
			absolute, err := filepath.Abs(address)
			if err != nil {
				return "", "", err
			}
			address = absolute
		}
		return "unix", filepath.Clean(address), nil
	}

	if strings.HasPrefix(target, "tcp://") {
		address := strings.TrimSpace(strings.TrimPrefix(target, "tcp://"))
		if _, _, err := net.SplitHostPort(address); err != nil {
			return "", "", invalid_params("tcp server target must be tcp://host:port")
		}
		return "tcp", address, nil
	}

	return "", "", invalid_params("server target must use unix://path.sock or tcp://host:port")
}

func serve_http_request(context *runtime_context, writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if request.URL.Path != "/" && request.URL.Path != "/rpc" {
		http.NotFound(writer, request)
		return
	}

	body, err := io.ReadAll(request.Body)
	if err != nil {
		http.Error(writer, "failed to read request body", http.StatusBadRequest)
		return
	}

	rpc_request, response := decode_request(body)
	if response == nil {
		result, call_err := dispatch(context, rpc_request)
		response = build_response(rpc_request.ID, result, call_err)
	}

	writer.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(writer).Encode(response)
}

func decode_request(data []byte) (*rpc_request, *rpc_response) {
	data = normalize_json_input(data)

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

func strip_utf8_bom(data []byte) []byte {
	if len(data) >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf {
		return data[3:]
	}

	return data
}

func normalize_json_input(data []byte) []byte {
	data = bytes.TrimSpace(data)
	data = strip_utf8_bom(data)

	if len(data) >= 6 && data[0] == 0xc3 && data[1] == 0xaf && data[2] == 0xc2 && data[3] == 0xbb && data[4] == 0xc2 && data[5] == 0xbf {
		return data[6:]
	}

	return data
}

func dispatch(context *runtime_context, request *rpc_request) (any, error) {
	handlers := map[string]rpc_handler{
		"system.describe":  handle_system_describe,
		"index.status":     handle_index_status,
		"roots.list":       handle_roots_list,
		"roots.add":        handle_roots_add,
		"roots.remove":     handle_roots_remove,
		"query":            handle_query,
		"query.common":     handle_query_common,
		"context.at":       handle_context_at,
		"symbols.find":     handle_symbols_find,
		"symbols.overview": handle_symbols_overview,
		"references.find":  handle_references_find,
		"calls.find":       handle_calls_find,
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
		"process_id":      context.process_id,
		"executable_path": context.executable_path,
		"cache_dir":       context.cache_dir,
		"languages":       supported_languages,
		"server_mode": map[string]any{
			"implemented": true,
			"active":      context.server_mode,
			"target":      context.server_target,
			"transports":  []string{"http+unix-socket", "http+tcp"},
		},
		"methods": []string{
			"system.describe",
			"index.status",
			"roots.list",
			"roots.add",
			"roots.remove",
			"query",
			"query.common",
			"context.at",
			"symbols.find",
			"symbols.overview",
			"references.find",
			"calls.find",
		},
	}, nil
}

func handle_index_status(context *runtime_context, _ json.RawMessage) (any, error) {
	state, err := load_state(context)
	if err != nil {
		return nil, err
	}

	last_query, err := load_optional_json(filepath.Join(context.cache_dir, "last-query.json"))
	if err != nil {
		return nil, err
	}

	last_symbols_overview, err := load_optional_json(filepath.Join(context.cache_dir, "last-symbols-overview.json"))
	if err != nil {
		return nil, err
	}

	analysis_cache, err := describe_analysis_cache(context)
	if err != nil {
		return nil, err
	}

	return map[string]any{
		"cache_dir":             context.cache_dir,
		"state_path":            context.state_path,
		"process_id":            context.process_id,
		"roots":                 state.Roots,
		"server_mode":           context.server_mode,
		"server_target":         context.server_target,
		"started_at":            context.started_at.Format(time.RFC3339Nano),
		"cache_files":           describe_cache_files(context.cache_dir, []string{"state.json", "last-query.json", "last-symbols-overview.json"}),
		"analysis_cache":        analysis_cache,
		"last_query":            last_query,
		"last_symbols_overview": last_symbols_overview,
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

	roots, include_patterns, exclude_patterns, err := decode_search_scope(context, parsed.Roots, parsed.Include, parsed.Exclude)
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
		"roots":         roots,
	})

	total_files := len(matches)
	matches = page_file_matches(matches, parsed.Offset, parsed.Limit)

	return map[string]any{
		"roots": roots,
		"summary": map[string]any{
			"language":       parsed.Language,
			"files_scanned":  files_scanned,
			"files_matched":  total_files,
			"files_returned": len(matches),
			"offset":         max(parsed.Offset, 0),
			"limit":          normalized_limit(parsed.Limit),
			"started_at":     started.Format(time.RFC3339Nano),
			"duration_ms":    time.Since(started).Milliseconds(),
		},
		"matches": matches,
	}, nil
}

func handle_symbols_overview(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed symbols_overview_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("symbols.overview params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}

	language, err := linked_language(parsed.Language)
	if err != nil {
		return nil, err
	}

	parser := tree_sitter.NewParser()
	defer parser.Close()

	if err := parser.SetLanguage(language); err != nil {
		return nil, err
	}

	roots, include_patterns, exclude_patterns, err := decode_search_scope(context, parsed.Roots, parsed.Include, parsed.Exclude)
	if err != nil {
		return nil, err
	}

	started := time.Now().UTC()
	max_symbols := parsed.MaxSymbols
	if max_symbols <= 0 {
		max_symbols = 10000
	}

	var files []symbol_file
	var files_scanned int
	var total_symbols int

	for _, root := range roots {
		root_files, scanned, symbols_found, err := overview_root(context, parsed.Language, root, include_patterns, exclude_patterns, parser, max_symbols-total_symbols)
		if err != nil {
			return nil, err
		}
		files = append(files, root_files...)
		files_scanned += scanned
		total_symbols += symbols_found
		if total_symbols >= max_symbols {
			break
		}
	}

	_ = touch_cache_file(filepath.Join(context.cache_dir, "last-symbols-overview.json"), map[string]any{
		"timestamp":      started.Format(time.RFC3339Nano),
		"language":       parsed.Language,
		"files_scanned":  files_scanned,
		"files_reported": len(files),
		"symbols":        total_symbols,
		"roots":          roots,
	})

	total_files := len(files)
	total_symbols_before_page := count_symbols_in_files(files)
	files = page_symbol_files(files, parsed.Offset, parsed.Limit)

	return map[string]any{
		"roots": roots,
		"summary": map[string]any{
			"language":         parsed.Language,
			"files_scanned":    files_scanned,
			"files_reported":   total_files,
			"files_returned":   len(files),
			"symbols":          total_symbols_before_page,
			"symbols_returned": count_symbols_in_files(files),
			"max_symbols":      max_symbols,
			"offset":           max(parsed.Offset, 0),
			"limit":            normalized_limit(parsed.Limit),
			"started_at":       started.Format(time.RFC3339Nano),
			"duration_ms":      time.Since(started).Milliseconds(),
		},
		"files": files,
	}, nil
}

func handle_symbols_find(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed symbols_find_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("symbols.find params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}

	language, err := linked_language(parsed.Language)
	if err != nil {
		return nil, err
	}

	parser := tree_sitter.NewParser()
	defer parser.Close()

	if err := parser.SetLanguage(language); err != nil {
		return nil, err
	}

	roots, include_patterns, exclude_patterns, err := decode_search_scope(context, parsed.Roots, parsed.Include, parsed.Exclude)
	if err != nil {
		return nil, err
	}

	started := time.Now().UTC()
	max_symbols := parsed.MaxSymbols
	if max_symbols <= 0 {
		max_symbols = 200
	}

	var files []symbol_file
	var files_scanned int
	var total_symbols int

	for _, root := range roots {
		root_files, scanned, _, err := overview_root(context, parsed.Language, root, include_patterns, exclude_patterns, parser, max_symbols-total_symbols)
		if err != nil {
			return nil, err
		}
		files_scanned += scanned
		for _, file := range root_files {
			filtered := filter_symbols(file.Symbols, parsed.Name, parsed.Kinds, parsed.MatchMode, max_symbols-total_symbols)
			if len(filtered) == 0 {
				continue
			}
			files = append(files, symbol_file{
				Path:     file.Path,
				Root:     file.Root,
				Relative: file.Relative,
				Symbols:  filtered,
			})
			total_symbols += len(filtered)
			if total_symbols >= max_symbols {
				break
			}
		}
		if total_symbols >= max_symbols {
			break
		}
	}

	total_files := len(files)
	total_symbols_before_page := count_symbols_in_files(files)
	files = page_symbol_files(files, parsed.Offset, parsed.Limit)

	return map[string]any{
		"roots": roots,
		"summary": map[string]any{
			"language":         parsed.Language,
			"files_scanned":    files_scanned,
			"files_reported":   total_files,
			"files_returned":   len(files),
			"symbols":          total_symbols_before_page,
			"symbols_returned": count_symbols_in_files(files),
			"match_mode":       normalize_match_mode(parsed.MatchMode),
			"offset":           max(parsed.Offset, 0),
			"limit":            normalized_limit(parsed.Limit),
			"started_at":       started.Format(time.RFC3339Nano),
			"duration_ms":      time.Since(started).Milliseconds(),
		},
		"files": files,
	}, nil
}

func handle_calls_find(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed calls_find_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("calls.find params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}
	if strings.TrimSpace(parsed.Callee) == "" {
		return nil, invalid_params("callee is required")
	}

	language, err := linked_language(parsed.Language)
	if err != nil {
		return nil, err
	}

	parser := tree_sitter.NewParser()
	defer parser.Close()

	if err := parser.SetLanguage(language); err != nil {
		return nil, err
	}

	roots, include_patterns, exclude_patterns, err := decode_search_scope(context, parsed.Roots, parsed.Include, parsed.Exclude)
	if err != nil {
		return nil, err
	}

	started := time.Now().UTC()
	max_calls := parsed.MaxCalls
	if max_calls <= 0 {
		max_calls = 200
	}

	var files []call_file
	var files_scanned int
	var total_calls int

	for _, root := range roots {
		root_files, scanned, calls_found, err := calls_root(context, parsed.Language, root, include_patterns, exclude_patterns, parser, parsed.Callee, parsed.MatchMode, max_calls-total_calls)
		if err != nil {
			return nil, err
		}
		files = append(files, root_files...)
		files_scanned += scanned
		total_calls += calls_found
		if total_calls >= max_calls {
			break
		}
	}

	total_files := len(files)
	total_calls_before_page := count_calls_in_files(files)
	files = page_call_files(files, parsed.Offset, parsed.Limit)

	return map[string]any{
		"roots": roots,
		"summary": map[string]any{
			"language":       parsed.Language,
			"files_scanned":  files_scanned,
			"files_reported": total_files,
			"files_returned": len(files),
			"calls":          total_calls_before_page,
			"calls_returned": count_calls_in_files(files),
			"match_mode":     normalize_match_mode(parsed.MatchMode),
			"offset":         max(parsed.Offset, 0),
			"limit":          normalized_limit(parsed.Limit),
			"started_at":     started.Format(time.RFC3339Nano),
			"duration_ms":    time.Since(started).Milliseconds(),
		},
		"files": files,
	}, nil
}

func handle_references_find(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed references_find_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("references.find params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}
	if strings.TrimSpace(parsed.Name) == "" {
		return nil, invalid_params("name is required")
	}

	language, err := linked_language(parsed.Language)
	if err != nil {
		return nil, err
	}

	parser := tree_sitter.NewParser()
	defer parser.Close()

	if err := parser.SetLanguage(language); err != nil {
		return nil, err
	}

	roots, include_patterns, exclude_patterns, err := decode_search_scope(context, parsed.Roots, parsed.Include, parsed.Exclude)
	if err != nil {
		return nil, err
	}

	started := time.Now().UTC()
	max_references := parsed.MaxReferences
	if max_references <= 0 {
		max_references = 200
	}

	var files []reference_file
	var files_scanned int
	var total_references int

	for _, root := range roots {
		root_files, scanned, references_found, err := references_root(context, parsed.Language, root, include_patterns, exclude_patterns, parser, parsed.Name, parsed.Kinds, parsed.MatchMode, max_references-total_references)
		if err != nil {
			return nil, err
		}
		files = append(files, root_files...)
		files_scanned += scanned
		total_references += references_found
		if total_references >= max_references {
			break
		}
	}

	total_files := len(files)
	total_references_before_page := count_references_in_files(files)
	files = page_reference_files(files, parsed.Offset, parsed.Limit)

	return map[string]any{
		"roots": roots,
		"summary": map[string]any{
			"language":            parsed.Language,
			"files_scanned":       files_scanned,
			"files_reported":      total_files,
			"files_returned":      len(files),
			"references":          total_references_before_page,
			"references_returned": count_references_in_files(files),
			"match_mode":          normalize_match_mode(parsed.MatchMode),
			"offset":              max(parsed.Offset, 0),
			"limit":               normalized_limit(parsed.Limit),
			"started_at":          started.Format(time.RFC3339Nano),
			"duration_ms":         time.Since(started).Milliseconds(),
		},
		"files": files,
	}, nil
}

func handle_query_common(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed query_common_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("query.common params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}
	if strings.TrimSpace(parsed.Preset) == "" {
		return nil, invalid_params("preset is required")
	}

	switch parsed.Preset {
	case "functions.by_name":
		return handle_symbols_find(context, must_json(params_from_map(map[string]any{
			"language":    parsed.Language,
			"name":        parsed.Name,
			"kinds":       append([]string{}, append(parsed.Kinds, "function", "method")...),
			"roots":       parsed.Roots,
			"include":     parsed.Include,
			"exclude":     parsed.Exclude,
			"match_mode":  parsed.MatchMode,
			"max_symbols": parsed.MaxItems,
			"limit":       parsed.Limit,
			"offset":      parsed.Offset,
		})))
	case "types.by_name":
		return handle_symbols_find(context, must_json(params_from_map(map[string]any{
			"language":    parsed.Language,
			"name":        parsed.Name,
			"kinds":       append([]string{}, append(parsed.Kinds, "type", "class", "interface", "struct", "trait", "enum", "module", "impl")...),
			"roots":       parsed.Roots,
			"include":     parsed.Include,
			"exclude":     parsed.Exclude,
			"match_mode":  parsed.MatchMode,
			"max_symbols": parsed.MaxItems,
			"limit":       parsed.Limit,
			"offset":      parsed.Offset,
		})))
	case "calls.by_name":
		return handle_calls_find(context, must_json(params_from_map(map[string]any{
			"language":   parsed.Language,
			"callee":     parsed.Name,
			"roots":      parsed.Roots,
			"include":    parsed.Include,
			"exclude":    parsed.Exclude,
			"match_mode": parsed.MatchMode,
			"max_calls":  parsed.MaxItems,
			"limit":      parsed.Limit,
			"offset":     parsed.Offset,
		})))
	case "references.by_name":
		return handle_references_find(context, must_json(params_from_map(map[string]any{
			"language":       parsed.Language,
			"name":           parsed.Name,
			"kinds":          parsed.Kinds,
			"roots":          parsed.Roots,
			"include":        parsed.Include,
			"exclude":        parsed.Exclude,
			"match_mode":     parsed.MatchMode,
			"max_references": parsed.MaxItems,
			"limit":          parsed.Limit,
			"offset":         parsed.Offset,
		})))
	default:
		return nil, invalid_params(fmt.Sprintf("unsupported preset: %s", parsed.Preset))
	}
}

func handle_context_at(context *runtime_context, params json.RawMessage) (any, error) {
	var parsed context_at_params
	if err := json.Unmarshal(non_nil_params(params), &parsed); err != nil {
		return nil, invalid_params("context.at params must be an object")
	}

	if strings.TrimSpace(parsed.Language) == "" {
		return nil, invalid_params("language is required")
	}
	if strings.TrimSpace(parsed.Path) == "" {
		return nil, invalid_params("path is required")
	}
	if parsed.Row < 0 || parsed.Column < 0 {
		return nil, invalid_params("row and column must be >= 0")
	}

	language, err := linked_language(parsed.Language)
	if err != nil {
		return nil, err
	}

	parser := tree_sitter.NewParser()
	defer parser.Close()

	if err := parser.SetLanguage(language); err != nil {
		return nil, err
	}

	file_path, root, relative, err := resolve_context_file(context, parsed.Path, parsed.Roots)
	if err != nil {
		return nil, err
	}

	source, err := os.ReadFile(file_path)
	if err != nil {
		return nil, err
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		return nil, fmt.Errorf("tree-sitter parse failed for %s", file_path)
	}
	defer tree.Close()

	target_point := tree_sitter.Point{Row: uint(parsed.Row), Column: uint(parsed.Column)}
	node := tree.RootNode().NamedDescendantForPointRange(target_point, target_point)
	if node == nil {
		node = tree.RootNode()
	}

	innermost := describe_node_context(node, source)
	blocks := enclosing_blocks(node, source)
	symbols := enclosing_symbols(node, source)

	return map[string]any{
		"language": parsed.Language,
		"path":     file_path,
		"root":     root,
		"relative": relative,
		"point": map[string]any{
			"row":    parsed.Row,
			"column": parsed.Column,
		},
		"innermost": innermost,
		"blocks":    blocks,
		"symbols":   symbols,
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
	return write_atomic_file(context.state_path, data)
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

func decode_search_scope(
	context *runtime_context,
	explicit_roots []string,
	include_raw json.RawMessage,
	exclude_raw json.RawMessage,
) ([]string, []string, []string, error) {
	roots, err := resolve_roots(context, explicit_roots)
	if err != nil {
		return nil, nil, nil, err
	}

	include_patterns, err := decode_patterns(include_raw)
	if err != nil {
		return nil, nil, nil, err
	}

	exclude_patterns, err := decode_patterns(exclude_raw)
	if err != nil {
		return nil, nil, nil, err
	}

	return roots, include_patterns, exclude_patterns, nil
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

func overview_root(
	context *runtime_context,
	language_name string,
	root string,
	include_patterns []string,
	exclude_patterns []string,
	parser *tree_sitter.Parser,
	remaining_symbols int,
) ([]symbol_file, int, int, error) {
	var files []symbol_file
	var files_scanned int
	var total_symbols int

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

		if total_symbols >= remaining_symbols {
			return io.EOF
		}

		files_scanned++
		file_symbols, err := overview_file(context, language_name, path, root, relative, parser, remaining_symbols-total_symbols)
		if err != nil {
			return err
		}
		if len(file_symbols.Symbols) > 0 {
			files = append(files, file_symbols)
			total_symbols += len(file_symbols.Symbols)
		}
		return nil
	})

	if errors.Is(err, io.EOF) {
		err = nil
	}

	return files, files_scanned, total_symbols, err
}

func overview_file(
	context *runtime_context,
	language_name string,
	path string,
	root string,
	relative string,
	parser *tree_sitter.Parser,
	remaining_symbols int,
) (symbol_file, error) {
	analysis, err := load_or_create_analysis(context, language_name, path, parser)
	if err != nil {
		return symbol_file{}, err
	}

	symbols := slice_prefix(analysis.Symbols, remaining_symbols)

	return symbol_file{
		Path:     path,
		Root:     root,
		Relative: relative,
		Symbols:  symbols,
	}, nil
}

func resolve_context_file(context *runtime_context, path string, explicit_roots []string) (string, string, string, error) {
	if filepath.IsAbs(path) {
		absolute := filepath.Clean(path)
		info, err := os.Stat(absolute)
		if err != nil {
			return "", "", "", err
		}
		if info.IsDir() {
			return "", "", "", invalid_params("path must be a file, not a directory")
		}

		roots, err := resolve_roots(context, explicit_roots)
		if err != nil && !strings.Contains(err.Error(), "no roots configured") {
			return "", "", "", err
		}

		best_root := ""
		best_relative := filepath.Base(absolute)
		for _, root := range roots {
			relative, rel_err := filepath.Rel(root, absolute)
			if rel_err == nil && !strings.HasPrefix(filepath.ToSlash(relative), "../") {
				best_root = root
				best_relative = filepath.ToSlash(relative)
				break
			}
		}

		return absolute, best_root, best_relative, nil
	}

	roots, err := resolve_roots(context, explicit_roots)
	if err != nil {
		return "", "", "", err
	}

	relative := filepath.ToSlash(path)
	for _, root := range roots {
		candidate := filepath.Join(root, filepath.FromSlash(relative))
		info, stat_err := os.Stat(candidate)
		if stat_err == nil && !info.IsDir() {
			return filepath.Clean(candidate), root, relative, nil
		}
	}

	return "", "", "", invalid_params(fmt.Sprintf("file not found in roots: %s", path))
}

func calls_root(
	context *runtime_context,
	language_name string,
	root string,
	include_patterns []string,
	exclude_patterns []string,
	parser *tree_sitter.Parser,
	callee string,
	match_mode string,
	remaining_calls int,
) ([]call_file, int, int, error) {
	var files []call_file
	var files_scanned int
	var total_calls int

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

		if total_calls >= remaining_calls {
			return io.EOF
		}

		files_scanned++
		file_calls, err := calls_file(context, language_name, path, root, relative, parser, callee, match_mode, remaining_calls-total_calls)
		if err != nil {
			return err
		}
		if len(file_calls.Calls) > 0 {
			files = append(files, file_calls)
			total_calls += len(file_calls.Calls)
		}
		return nil
	})

	if errors.Is(err, io.EOF) {
		err = nil
	}

	return files, files_scanned, total_calls, err
}

func references_root(
	context *runtime_context,
	language_name string,
	root string,
	include_patterns []string,
	exclude_patterns []string,
	parser *tree_sitter.Parser,
	name string,
	kinds []string,
	match_mode string,
	remaining_references int,
) ([]reference_file, int, int, error) {
	var files []reference_file
	var files_scanned int
	var total_references int

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

		if total_references >= remaining_references {
			return io.EOF
		}

		files_scanned++
		file_references, err := references_file(context, language_name, path, root, relative, parser, name, kinds, match_mode, remaining_references-total_references)
		if err != nil {
			return err
		}
		if len(file_references.References) > 0 {
			files = append(files, file_references)
			total_references += len(file_references.References)
		}
		return nil
	})

	if errors.Is(err, io.EOF) {
		err = nil
	}

	return files, files_scanned, total_references, err
}

func calls_file(
	context *runtime_context,
	language_name string,
	path string,
	root string,
	relative string,
	parser *tree_sitter.Parser,
	callee string,
	match_mode string,
	remaining_calls int,
) (call_file, error) {
	analysis, err := load_or_create_analysis(context, language_name, path, parser)
	if err != nil {
		return call_file{}, err
	}

	calls := filter_calls(analysis.Calls, callee, match_mode, remaining_calls)

	return call_file{
		Path:     path,
		Root:     root,
		Relative: relative,
		Calls:    calls,
	}, nil
}

func references_file(
	context *runtime_context,
	language_name string,
	path string,
	root string,
	relative string,
	parser *tree_sitter.Parser,
	name string,
	kinds []string,
	match_mode string,
	remaining_references int,
) (reference_file, error) {
	analysis, err := load_or_create_analysis(context, language_name, path, parser)
	if err != nil {
		return reference_file{}, err
	}

	references := filter_references(analysis.References, name, kinds, match_mode, remaining_references)

	return reference_file{
		Path:       path,
		Root:       root,
		Relative:   relative,
		References: references,
	}, nil
}

func collect_symbols(
	source []byte,
	node *tree_sitter.Node,
	container string,
	remaining_symbols int,
	symbols *[]symbol_overview,
) {
	if node == nil || len(*symbols) >= remaining_symbols {
		return
	}

	next_container := container
	kind := symbol_category(node.GrammarName())
	if kind != "" {
		name := symbol_name(node, source)
		if name != "" {
			*symbols = append(*symbols, symbol_overview{
				Kind:        kind,
				GrammarKind: node.GrammarName(),
				Name:        name,
				Container:   container,
				Signature:   symbol_signature(node, source),
				StartByte:   node.StartByte(),
				EndByte:     node.EndByte(),
				Start:       point_from_tree(node.StartPosition()),
				End:         point_from_tree(node.EndPosition()),
			})
			next_container = name
		}
	}

	for index := uint(0); index < node.NamedChildCount(); index++ {
		collect_symbols(source, node.NamedChild(index), next_container, remaining_symbols, symbols)
		if len(*symbols) >= remaining_symbols {
			return
		}
	}
}

func collect_calls(
	source []byte,
	node *tree_sitter.Node,
	callee string,
	match_mode string,
	remaining_calls int,
	calls *[]call_match,
) {
	if node == nil || len(*calls) >= remaining_calls {
		return
	}

	if is_call_kind(node.GrammarName()) {
		target_text := call_target_text(node, source)
		if matches_text(target_text, callee, match_mode) {
			*calls = append(*calls, call_match{
				Callee:     target_text,
				Expression: symbol_signature(node, source),
				Kind:       node.GrammarName(),
				StartByte:  node.StartByte(),
				EndByte:    node.EndByte(),
				Start:      point_from_tree(node.StartPosition()),
				End:        point_from_tree(node.EndPosition()),
			})
		}
	}

	for index := uint(0); index < node.NamedChildCount(); index++ {
		collect_calls(source, node.NamedChild(index), callee, match_mode, remaining_calls, calls)
		if len(*calls) >= remaining_calls {
			return
		}
	}
}

func collect_references(
	source []byte,
	node *tree_sitter.Node,
	name string,
	kinds []string,
	match_mode string,
	remaining_references int,
	references *[]reference_match,
) {
	if node == nil || len(*references) >= remaining_references {
		return
	}

	if is_reference_candidate(node.GrammarName()) {
		reference_name := compact_text(node.Utf8Text(source))
		if reference_name != "" && matches_text(reference_name, name, match_mode) && !is_definition_name_reference(node, source) && matches_reference_kind(node.GrammarName(), kinds) {
			*references = append(*references, reference_match{
				Name:       reference_name,
				Kind:       node.GrammarName(),
				Expression: reference_expression(node, source),
				StartByte:  node.StartByte(),
				EndByte:    node.EndByte(),
				Start:      point_from_tree(node.StartPosition()),
				End:        point_from_tree(node.EndPosition()),
			})
		}
	}

	for index := uint(0); index < node.NamedChildCount(); index++ {
		collect_references(source, node.NamedChild(index), name, kinds, match_mode, remaining_references, references)
		if len(*references) >= remaining_references {
			return
		}
	}
}

func enclosing_blocks(node *tree_sitter.Node, source []byte) []node_context {
	var blocks []node_context
	for current := node; current != nil; current = current.Parent() {
		if is_block_kind(current.GrammarName()) {
			blocks = append([]node_context{describe_node_context(current, source)}, blocks...)
		}
	}
	return blocks
}

func enclosing_symbols(node *tree_sitter.Node, source []byte) []node_context {
	var symbols []node_context
	for current := node; current != nil; current = current.Parent() {
		if symbol_category(current.GrammarName()) != "" {
			symbols = append([]node_context{describe_node_context(current, source)}, symbols...)
		}
	}
	return symbols
}

func describe_node_context(node *tree_sitter.Node, source []byte) node_context {
	return node_context{
		Kind:        block_or_symbol_kind(node),
		GrammarKind: node.GrammarName(),
		Name:        symbol_name(node, source),
		Signature:   symbol_signature(node, source),
		StartByte:   node.StartByte(),
		EndByte:     node.EndByte(),
		Start:       point_from_tree(node.StartPosition()),
		End:         point_from_tree(node.EndPosition()),
	}
}

func block_or_symbol_kind(node *tree_sitter.Node) string {
	if kind := symbol_category(node.GrammarName()); kind != "" {
		return kind
	}
	if is_block_kind(node.GrammarName()) {
		return "block"
	}
	return node.Kind()
}

func symbol_category(kind string) string {
	switch kind {
	case "package_clause", "namespace_definition":
		return "package"
	case "function_declaration", "function_definition", "function_item":
		return "function"
	case "method_declaration", "method_definition":
		return "method"
	case "class_declaration", "class_definition":
		return "class"
	case "interface_declaration", "interface_definition":
		return "interface"
	case "enum_declaration", "enum_definition", "enum_specifier", "enum_item":
		return "enum"
	case "struct_specifier", "struct_item":
		return "struct"
	case "trait_declaration", "trait_definition", "trait_item":
		return "trait"
	case "type_spec", "type_definition", "type_item", "type_alias_statement":
		return "type"
	case "impl_item":
		return "impl"
	case "module", "module_definition", "module_declaration", "mod_item", "namespace_name":
		return "module"
	}

	return ""
}

func is_block_kind(kind string) bool {
	switch kind {
	case "block", "statement_block", "compound_statement", "declaration_list", "class_body", "field_declaration_list", "interface_body", "enum_body", "impl_body", "namespace_body", "module_body":
		return true
	}
	return false
}

func is_call_kind(kind string) bool {
	switch kind {
	case "call_expression", "call", "invocation_expression":
		return true
	}
	return false
}

func is_reference_candidate(kind string) bool {
	return is_identifier_kind(kind)
}

func is_definition_name_reference(node *tree_sitter.Node, source []byte) bool {
	parent := node.Parent()
	for depth := 0; parent != nil && depth < 3; depth++ {
		if symbol_category(parent.GrammarName()) != "" && symbol_name(parent, source) == compact_text(node.Utf8Text(source)) {
			return true
		}
		parent = parent.Parent()
	}

	return false
}

func reference_expression(node *tree_sitter.Node, source []byte) string {
	parent := node.Parent()
	for depth := 0; parent != nil && depth < 2; depth++ {
		text := symbol_signature(parent, source)
		if text != "" {
			return text
		}
		parent = parent.Parent()
	}

	return symbol_signature(node, source)
}

func call_target_text(node *tree_sitter.Node, source []byte) string {
	for _, field_name := range []string{"function", "name", "call", "callee"} {
		if child := node.ChildByFieldName(field_name); child != nil {
			if text := compact_text(child.Utf8Text(source)); text != "" {
				return text
			}
		}
	}

	if node.NamedChildCount() > 0 {
		if child := node.NamedChild(0); child != nil {
			return compact_text(child.Utf8Text(source))
		}
	}

	return ""
}

func symbol_name(node *tree_sitter.Node, source []byte) string {
	for _, field_name := range []string{"name", "declarator", "label"} {
		if child := node.ChildByFieldName(field_name); child != nil {
			if text := identifier_text(child, source, 4); text != "" {
				return text
			}
		}
	}

	return identifier_text(node, source, 3)
}

func identifier_text(node *tree_sitter.Node, source []byte, depth int) string {
	if node == nil || depth < 0 {
		return ""
	}

	kind := node.GrammarName()
	text := strings.TrimSpace(node.Utf8Text(source))
	if is_identifier_kind(kind) && text != "" {
		return text
	}

	for index := uint(0); index < node.NamedChildCount(); index++ {
		if child := node.NamedChild(index); child != nil {
			if text := identifier_text(child, source, depth-1); text != "" {
				return text
			}
		}
	}

	return ""
}

func is_identifier_kind(kind string) bool {
	switch {
	case kind == "identifier":
		return true
	case strings.HasSuffix(kind, "identifier"):
		return true
	case kind == "name", kind == "qualified_name", kind == "namespace_name":
		return true
	}

	return false
}

func symbol_signature(node *tree_sitter.Node, source []byte) string {
	text := compact_text(node.Utf8Text(source))
	if text == "" {
		return ""
	}

	if index := strings.Index(text, "{"); index > 0 {
		text = text[:index]
	}

	text = strings.Join(strings.Fields(text), " ")
	if len(text) > 180 {
		return text[:177] + "..."
	}

	return text
}

func compact_text(text string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(text)), " ")
}

func filter_symbols(
	symbols []symbol_overview,
	name string,
	kinds []string,
	match_mode string,
	remaining int,
) []symbol_overview {
	allowed_kinds := map[string]struct{}{}
	for _, kind := range kinds {
		if trimmed := strings.TrimSpace(kind); trimmed != "" {
			allowed_kinds[strings.ToLower(trimmed)] = struct{}{}
		}
	}

	filtered := make([]symbol_overview, 0, len(symbols))
	for _, symbol := range symbols {
		if len(allowed_kinds) > 0 {
			if _, ok := allowed_kinds[strings.ToLower(symbol.Kind)]; !ok {
				continue
			}
		}
		if !matches_text(symbol.Name, name, normalize_match_mode(match_mode)) {
			continue
		}
		filtered = append(filtered, symbol)
		if len(filtered) >= remaining {
			break
		}
	}

	return filtered
}

func matches_reference_kind(kind string, kinds []string) bool {
	if len(kinds) == 0 {
		return true
	}

	for _, allowed := range kinds {
		if strings.EqualFold(strings.TrimSpace(allowed), kind) {
			return true
		}
	}

	return false
}

func normalize_match_mode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", "exact":
		return "exact"
	case "contains", "prefix", "suffix", "regex":
		return strings.ToLower(strings.TrimSpace(mode))
	default:
		return "exact"
	}
}

func matches_text(value string, needle string, match_mode string) bool {
	if strings.TrimSpace(needle) == "" {
		return true
	}

	value = strings.TrimSpace(value)
	needle = strings.TrimSpace(needle)

	switch normalize_match_mode(match_mode) {
	case "contains":
		return strings.Contains(value, needle)
	case "prefix":
		return strings.HasPrefix(value, needle)
	case "suffix":
		return strings.HasSuffix(value, needle)
	case "regex":
		regex, err := regexp.Compile(needle)
		if err != nil {
			return false
		}
		return regex.MatchString(value)
	default:
		return value == needle
	}
}

func params_from_map(values map[string]any) map[string]any {
	params := map[string]any{}
	for key, value := range values {
		switch typed := value.(type) {
		case json.RawMessage:
			if len(typed) == 0 {
				continue
			}
			params[key] = json.RawMessage(typed)
		case []string:
			if len(typed) == 0 {
				continue
			}
			params[key] = typed
		case string:
			if strings.TrimSpace(typed) == "" {
				continue
			}
			params[key] = typed
		case int:
			if typed <= 0 {
				continue
			}
			params[key] = typed
		default:
			if value != nil {
				params[key] = value
			}
		}
	}
	return params
}

func effective_limit(limit int) int {
	if limit <= 0 {
		return 100
	}
	return limit
}

func normalized_limit(limit int) int {
	return effective_limit(limit)
}

func page_bounds(total int, offset int, limit int) (int, int) {
	if offset < 0 {
		offset = 0
	}
	if offset >= total {
		return total, total
	}
	limit = effective_limit(limit)
	end := offset + limit
	if end > total {
		end = total
	}
	return offset, end
}

func page_file_matches(matches []file_match, offset int, limit int) []file_match {
	start, end := page_bounds(len(matches), offset, limit)
	return matches[start:end]
}

func page_symbol_files(files []symbol_file, offset int, limit int) []symbol_file {
	start, end := page_bounds(len(files), offset, limit)
	return files[start:end]
}

func page_call_files(files []call_file, offset int, limit int) []call_file {
	start, end := page_bounds(len(files), offset, limit)
	return files[start:end]
}

func page_reference_files(files []reference_file, offset int, limit int) []reference_file {
	start, end := page_bounds(len(files), offset, limit)
	return files[start:end]
}

func count_symbols_in_files(files []symbol_file) int {
	total := 0
	for _, file := range files {
		total += len(file.Symbols)
	}
	return total
}

func count_calls_in_files(files []call_file) int {
	total := 0
	for _, file := range files {
		total += len(file.Calls)
	}
	return total
}

func count_references_in_files(files []reference_file) int {
	total := 0
	for _, file := range files {
		total += len(file.References)
	}
	return total
}

func filter_calls(all []call_match, callee string, match_mode string, remaining_calls int) []call_match {
	filtered := make([]call_match, 0, min(len(all), remaining_calls))
	normalized_mode := normalize_match_mode(match_mode)
	for _, call := range all {
		if !matches_text(call.Callee, callee, normalized_mode) {
			continue
		}
		filtered = append(filtered, call)
		if len(filtered) >= remaining_calls {
			break
		}
	}
	return filtered
}

func filter_references(all []reference_match, name string, kinds []string, match_mode string, remaining_references int) []reference_match {
	filtered := make([]reference_match, 0, min(len(all), remaining_references))
	allowed_kinds := map[string]struct{}{}
	for _, kind := range kinds {
		if strings.TrimSpace(kind) != "" {
			allowed_kinds[kind] = struct{}{}
		}
	}

	normalized_mode := normalize_match_mode(match_mode)
	for _, reference := range all {
		if len(allowed_kinds) > 0 {
			if _, ok := allowed_kinds[reference.Kind]; !ok {
				continue
			}
		}
		if !matches_text(reference.Name, name, normalized_mode) {
			continue
		}
		filtered = append(filtered, reference)
		if len(filtered) >= remaining_references {
			break
		}
	}
	return filtered
}

func slice_prefix[T any](items []T, limit int) []T {
	if limit <= 0 || len(items) <= limit {
		return append([]T{}, items...)
	}
	return append([]T{}, items[:limit]...)
}

func load_or_create_analysis(
	context *runtime_context,
	language_name string,
	path string,
	parser *tree_sitter.Parser,
) (*analysis_cache_entry, error) {
	entry, err := load_analysis_cache_entry(context, language_name, path)
	if err != nil {
		return nil, err
	}
	if entry != nil {
		return entry, nil
	}

	source, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		return nil, fmt.Errorf("tree-sitter parse failed for %s", path)
	}
	defer tree.Close()

	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}

	symbols := make([]symbol_overview, 0, 64)
	collect_symbols(source, tree.RootNode(), "", int(^uint(0)>>1), &symbols)

	calls := make([]call_match, 0, 64)
	collect_calls(source, tree.RootNode(), "", "contains", int(^uint(0)>>1), &calls)

	references := make([]reference_match, 0, 128)
	collect_references(source, tree.RootNode(), "", nil, "contains", int(^uint(0)>>1), &references)

	entry = &analysis_cache_entry{
		Version:    1,
		Language:   language_name,
		Path:       filepath.Clean(path),
		Size:       info.Size(),
		ModifiedAt: info.ModTime().UTC().Format(time.RFC3339Nano),
		Symbols:    symbols,
		Calls:      calls,
		References: references,
	}

	if err := save_analysis_cache_entry(context, entry); err != nil {
		return nil, err
	}

	return entry, nil
}

func load_analysis_cache_entry(context *runtime_context, language_name string, path string) (*analysis_cache_entry, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}

	cache_path := analysis_cache_path(context, language_name, path)
	data, err := os.ReadFile(cache_path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}

	var entry analysis_cache_entry
	if err := json.Unmarshal(data, &entry); err != nil {
		return nil, nil
	}

	if entry.Version != 1 {
		return nil, nil
	}
	if entry.Language != language_name {
		return nil, nil
	}
	if filepath.Clean(entry.Path) != filepath.Clean(path) {
		return nil, nil
	}
	if entry.Size != info.Size() {
		return nil, nil
	}
	if entry.ModifiedAt != info.ModTime().UTC().Format(time.RFC3339Nano) {
		return nil, nil
	}

	return &entry, nil
}

func save_analysis_cache_entry(context *runtime_context, entry *analysis_cache_entry) error {
	cache_dir := filepath.Join(context.cache_dir, "analysis")
	if err := os.MkdirAll(cache_dir, 0o755); err != nil {
		return err
	}

	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}

	return write_atomic_file(analysis_cache_path(context, entry.Language, entry.Path), data)
}

func analysis_cache_path(context *runtime_context, language_name string, path string) string {
	sum := sha1.Sum([]byte(language_name + "\n" + filepath.Clean(path)))
	return filepath.Join(context.cache_dir, "analysis", fmt.Sprintf("%x.json", sum))
}

func describe_analysis_cache(context *runtime_context) (map[string]any, error) {
	cache_dir := filepath.Join(context.cache_dir, "analysis")
	if err := os.MkdirAll(cache_dir, 0o755); err != nil {
		return nil, err
	}

	var files int
	var total_size int64
	latest_modified_at := ""

	err := filepath.WalkDir(cache_dir, func(path string, entry fs.DirEntry, walk_err error) error {
		if walk_err != nil {
			return walk_err
		}
		if entry.IsDir() {
			return nil
		}

		info, err := entry.Info()
		if err != nil {
			return err
		}

		files++
		total_size += info.Size()
		modified_at := info.ModTime().UTC().Format(time.RFC3339Nano)
		if modified_at > latest_modified_at {
			latest_modified_at = modified_at
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	return map[string]any{
		"dir":                cache_dir,
		"files":              files,
		"total_size":         total_size,
		"latest_modified_at": latest_modified_at,
	}, nil
}

func must_json(value any) json.RawMessage {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return json.RawMessage(data)
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
	return write_atomic_file(path, data)
}

func write_atomic_file(path string, data []byte) error {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}

	temp_name := fmt.Sprintf(".%s.%d.%d.tmp", filepath.Base(path), os.Getpid(), time.Now().UnixNano())
	temp_path := filepath.Join(directory, temp_name)

	file, err := os.OpenFile(temp_path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}

	remove_temp := true
	defer func() {
		if remove_temp {
			_ = os.Remove(temp_path)
		}
	}()

	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}

	if err := os.Rename(temp_path, path); err != nil {
		_ = os.Remove(path)
		if second_err := os.Rename(temp_path, path); second_err != nil {
			return err
		}
	}

	remove_temp = false
	return nil
}

func describe_cache_files(cache_dir string, names []string) []map[string]any {
	files := make([]map[string]any, 0, len(names))

	for _, name := range names {
		path := filepath.Join(cache_dir, name)
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		files = append(files, map[string]any{
			"name":        name,
			"path":        path,
			"size":        info.Size(),
			"modified_at": info.ModTime().UTC().Format(time.RFC3339Nano),
		})
	}

	return files
}

func load_optional_json(path string) (any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}

	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		return nil, fmt.Errorf("invalid cache json at %s: %w", path, err)
	}

	return value, nil
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
