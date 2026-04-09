# ceretree

ceretree is a tool that allows querying source and text files recursively across one or more folders through a jsonrpc protocol
the same static standalone binary can be used in cli one shot mode passing the raw rpc request or in server mode
ceretree will monitor files in realtime in server mode and will reload data in cli mode
in both modes ceretree will cache next to the executable in a .ceretree-cache folder to speed up querying

the basic rpc command has 2 args a treesitter query and
an optional relative glob path for inclusion and a relative glob path for exclusion of files with double star support
by default all registered folders are searched recursively

another rpc command allows adding and removing folders from the monitored and queryable roots

we should support all official treesitter languages available, c/c++ golang rust js/ts php lua python bash batch powershell are the must have

we want to be skill and mcp friendly in the implementation
the tool is targeted to ai agents for coding to allow understanding code bases, symbols around the source tree, signatures, call trees, callsites and similar exploration tasks
also add other useful one shot rpc commands for common cases in the scenario

the single static executable binary must include also any dependency in our case the treesitter runtime and grammars

we also need a skill.md file or folder that enables the ceretree tool for an ai agent and relative installation instructions in README.md

server commands, cache, file monitoring, multifile treesitter queries over globs, useful rpc commands and useful features should make a skill.md that lets an agent explore source code in a performant and powerful way
we also need a test suite with common examples such as finding all calls to a function, all functions with a certain signature, and other useful cases
if new commands are needed or if some common treesitter queries can be synthesized into shorter rpc commands instead of long tedious raw queries we should add them
take inspiration from similar projects such as https://github.com/oraios/serena and run tests locally on small and larger code bases and in various languages such as wordpress and redis

the raw multifile query functionality must remain available and the skill must explain it so the agent can go to a lower level when needed

the skill file must explain clearly the motivations, capabilities, how to call the server, when to start and stop it, whether to use curl or something else to query it, and examples of server responses

there should be result limit and paging

transport direction and rationale:
- the preferred persistent server transport should be simple http request response over unix domain socket
- one request must produce one response and the protocol should stay jsonrpc 2.0 also over http to preserve method names, response shapes and errors across cli and server modes
- stdio server mode is less useful for many agent runtimes because they often do not expose a reusable persistent process handle across separate tool calls
- http over unix socket is preferred because an agent can start the server once with a long timeout and then call it many times through curl or equivalent stateless clients without needing a stdio handle
- the unix socket path should be chosen by the calling agent and passed explicitly on the cli so the caller can manage isolation and cleanup with a temporary unique path
- tcp ports should be avoided when possible to reduce namespace pollution and local security friction
- the transport should be designed around mainstream tools available by default on windows and linux; if windows powershell aliases are confusing the skill must explicitly say to use the real curl binary such as curl.exe on windows
- the skill must explain very clearly the exact lifecycle expected from an agent: choose a temporary socket path, spawn the server with a long timeout, keep it alive while doing multiple queries, use curl compatible post requests, then stop the server and delete the socket
- the skill must explain that the persistent server enables parallel or interleaved requests from separate agent steps because the transport is reattachable, unlike raw stdio in agent runtimes without process handle primitives
