# VCL for Varnish 5.2 and above

99.9% robbed from https://github.com/admingeekz/varnish-wordpress

## Usage

This VCL file expects a web server to be listening on 127.0.0.1:80, running Wordpress.

It suppports the efficient use of a Wordpress Multisite Network by preventing duplicate
static assets from appearing in the cache.
