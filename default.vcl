vcl 4.0;

# Varnish 6 configuration for wordpress
# AdminGeekZ Ltd <sales@admingeekz.com>
# URL: www.admingeekz.com/varnish-wordpress
# Version: 1.7 and then some
## updated -> Chris Fryer <c.j.fryer@lse.ac.uk>

backend dummy {
    # Not used
    .host = "localhost";
}

import std;
import goto;

sub vcl_init {
    new elastic_loadbalancer = goto.dns_director("{{ALB_HOSTNAME}}");
}

sub vcl_backend_fetch {
  set bereq.backend = elastic_loadbalancer.backend();
}

sub vcl_recv {

    # Health Checking
    if (req.url == "/varnishcheck") {
        return (synth(200, "OK"));
    }

    # Remove the "has_js" cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

    # Remove any Google Analytics based cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");

    # Are there cookies left with only spaces or that are empty?
    if (req.http.cookie ~ "^ *$") {
        unset req.http.cookie;
    }

    if (req.method != "GET" && req.method != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pass);
    }

    # Don't cache admin or login pages
    if (req.url ~ "wp-(login|admin)" ||
        req.url ~ "preview=true" ||
        req.url ~ "contact-form") {
        return (pass);
    }

    # Don't cache logged in users
    if (req.http.Cookie && req.http.Cookie ~ "(wordpress_|wordpress_logged_in|comment_author_)") {
        return(pass);
    }

    # Don't cache ajax requests, urls with ?nocache or comments/login/regiser
    if ((req.http.X-Requested-With == "XMLHttpRequest" && req.method != "GET") || 
        req.url ~ "nocache" || req.url ~ "(control.php|wp-comments-post.php|wp-login.php|register.php)") {
        return (pass);
    }

    # Don't cache requests for /simplesaml
    if (req.url ~ "^/simplesaml") {
        return (pass);
    }

    # Normalize the url - first remove any hashtags (shouldn't make it to the server anyway, but just in case)
    if (req.url ~ "\#") {
        set req.url=regsub(req.url,"\#.*$","");
    }
    # Normalize the url - remove Google tracking urls
    if (req.url ~ "\?") {
        set req.url=regsuball(req.url,"&(utm_source|utm_medium|utm_campaign|utm_content|utm_term|gclid)=([A-z0-9_\-]+)","");
        set req.url=regsuball(req.url,"\?(utm_source|utm_medium|utm_campaign|utm_content|utm_term|gclid)=([A-z0-9_\-]+)","?");
        set req.url=regsub(req.url,"\?&","?");
        set req.url=regsub(req.url,"\?$","");
    }

    # Remove all cookies if none of the above match
    unset req.http.Max-Age;
    unset req.http.Pragma;
    unset req.http.Cookie;
    return (hash);
}

sub vcl_backend_response {

    unset beresp.http.server;
    unset beresp.http.x-powered-by;
    unset beresp.http.pragma;

    # Uncomment this if you're happy to give away the structure of your VPC
    # set beresp.http.X-Backend = beresp.backend.name;

    # Don't cache error pages
    if (beresp.status >= 400) {
        set beresp.ttl = 0m;
        return(deliver);
    }

    if (bereq.url ~ "wp-(login|admin)" ||
        bereq.url ~ "preview=true" ||
        bereq.url ~ "contact-form" ||
        bereq.url ~ "^/simplesaml") {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    if (bereq.http.Cookie ~"(wp-postpass|wordpress_logged_in|comment_author_)") {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    # We have delivered all the cookies we need, so...
    unset beresp.http.Set-Cookie;

    if (bereq.http.X-Requested-With == "XMLHttpRequest" && bereq.url ~ "liveblog") {
        set beresp.ttl = 10s;
        set beresp.http.Cache-Control = "public";
        unset beresp.http.Expires;
        return (deliver);
    }

    if (bereq.url ~ "/files/"                    ||
        bereq.url ~ "/uploads/"                  ||
        bereq.url ~ "/blogs.dir/"                ||
        beresp.http.Content-Type ~ "image"       ||
        beresp.http.Content-Type ~ "javascript"  ||
        beresp.http.Content-Type ~ "text/css"    ||
        beresp.http.Content-Type ~ "x-font-woff") {

        set beresp.ttl = 1w;
        set beresp.http.Cache-Control = "public, stale-while-revalidate=1209600";
        set beresp.http.Expires = now + 1w;

        set beresp.keep = beresp.ttl + 1w;
        set beresp.grace = beresp.keep;
        return (deliver);
    }

    set beresp.ttl   = 2m;
    set beresp.grace = 1h;

    set beresp.http.Cache-Control = "public, stale-while-revalidate=3600, stale-if-error=3600";
    set beresp.http.Expires = now + 2m;

    return (deliver);
}

sub vcl_deliver {

    # Uncomment this if you're happy to give away the structure of your VPC
    # set resp.http.X-Cache-Server = server.identity;

    # Uncomment this if you want to see hits and misses
    # if (obj.hits > 0) {
    #     set resp.http.X-Hits  = obj.hits;
    #     set resp.http.X-Cache = "HIT";
    # } else {
    #     set resp.http.X-Cache = "MISS";
    # }

    # Warn downstream caches that the response is stale
    if (obj.ttl < 0s && resp.status == 200) {
       set resp.http.Warning = "110 Response is stale";
    }
}

sub vcl_hit {
    if (obj.ttl >= 0s) {
        return (deliver);
    }
    if (!std.healthy(req.backend_hint) && (obj.ttl + obj.grace > 0s)) {
        return (deliver);
    }
    return (miss);
}
