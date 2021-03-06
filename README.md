# LivioHTTPServer

This project was forked from https://github.com/robbiehanson/CocoaHTTPServer, and retains the BSD 2-clause license. The code has been wrapped into a framework, and is [Carthage ready](https://github.com/Carthage/Carthage).

Any questions about the code can probably be answered on the [wiki for the original project](https://github.com/robbiehanson/CocoaHTTPServer/wiki).

----

LivioHTTPServer is a small, lightweight, embeddable HTTP server for Mac OS X or iOS applications.

Sometimes developers need an embedded HTTP server in their app. Perhaps it's a server application with remote monitoring. Or perhaps it's a desktop application using HTTP for the communication backend. Or perhaps it's an iOS app providing over-the-air access to documents. Whatever your reason, LivioHTTPServer can get the job done. It provides:

-   Built in support for bonjour broadcasting
-   IPv4 and IPv6 support
-   Asynchronous networking using GCD and standard sockets
-   Password protection support
-   SSL/TLS encryption support
-   Extremely FAST and memory efficient
-   Extremely scalable (built entirely upon GCD)
-   Heavily commented code
-   Very easily extensible
-   WebDAV is supported too!
