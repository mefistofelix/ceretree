# ceretree

ceretree is a tool that allows to query source/text files one or more folders recursively with a jsonrpc protocol
the same static standalone binary that can be used (default) via cli passing the raw rpc request or in server mode which will listen on stdio/unixsocket/networksocket
ceretree will monitor in realtime via fs change events in server mode for folders/files changes or reload the data in cli mode
in both modes ceretree will cache along the executable in a .ceretree-cache folder the treesitter informations to sppedup querying

the basic rpc command has 2 args a treesitter query and
an optional relative glob path for inclusion and a relative glob path for exclusion of files (glob with double star support)
by default all registered folders are searched recursively

anoter rpc command allows to add and remove folders from the monitored and queryable folders

we should support all official treesitter languages available, c/c++ golang rust js/ts php lua python bash batch powershell are the must have

we want to be skill/mcp friendly in the implementation the cerebro tool is targeted to ai agents for coding to
allow understanding code bases symbols around the source tree, signature symbols discover calltrees callsites etc ect
also add other useful one shot rpc command for common cases in the scenario

wthe single static executable binary must incldue also any dependency in our case the treesitters dll/so

we also need a skill.md file or folder that enable the ceretree tool for an ai agent and relative installation instructions in README.md

server i comandi json la cache il monitoring dei files 
le query treesitter multifile su glob e i comandi rpc utili e le feature utili a fare uno skill.md da dare a 
un agent che possa esplorare il codice sorgente in modo performante e potente con query varie sul codice, 
serve anche una test suite con esempi common es trovare tutte le chiamate a una certa funzione tutte le funzioni con 
una certa signature e altre cose utili che ti vengono in mente, se servono nuovi comandi o si possono sintetizzare 
certe query molto comuni treesitter in comandi specifici senza dover specificare query lunghe e tediose aggiungiamoli 
prendiamo spunto da altri progetti simili come ad esempio https://github.com/oraios/serena e facciamo test in locale su 
code base piccole o anche più grandi e in vari linguaggi es wordpress redis

va lasciata la funzionalità di query grezze multifile etc e va spegato anche nello 
skill cos' l'agent se vuole fare qualcosa di particolare può andare più a basso livello

il file skill deve spiegare bene le motivazioni le funzionalità come chiamare il server come e quando farlo partire e 
stoppare se usare curl o altro per interrogarlo esempi di risposte del server etc

 servirà un limit/paging dei risultati