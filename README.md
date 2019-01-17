# Stencil
Stencil is a daemon written in Ruby that queries Consul's health API for changes in the health status of services, and uses ERB templates to generate new config files. 

# Why write this?
There are Daemon's that are part of supported open source projects that already have this basic functionality, however almost all of them are written in Go, a few are in Python. If you are a Puppet shop with skills already developed around ERB, it is most operable to continue to use ERB. As supporting ERB in another language amounts to reimplementing the Ruby interpretter, it makes sense to write a daemon in Ruby for this purpose.

# Installation
- Clone this repo
- Install gems `bundle install`

# Example Usage
- Create a template.json file:
```
{ "templates" : [ 
    { "template": "test.erb",
      "target": "/etc/nginx/nginx.conf",
      "service": "someapp",
      "callback": {
        "shell": "/bin/bash",
        "command": "systemctl restart nginx"
      }
    }
  ]
}
```
- Set consul host and template.json path in the environment
```
$ export CONSUL_HOST='http://consul.somedomain.com:8500
$ export TEMPLATES_FILE='/etc/stencil/template.json'
```
- Execute stencil.rb:
```
$ ruby stencil.rb 
I, [2019-01-02T13:37:33.104454 #28588]  INFO -- : Starting Stencil Daemon...
I, [2019-01-02T13:37:33.104552 #28588]  INFO -- : Parsing Config file...
D, [2019-01-02T13:37:33.104650 #28588] DEBUG -- : Consul Service Check: http://consul.somedomain.com:8500/v1/health/service/someapp
D, [2019-01-02T13:37:33.111910 #28588] DEBUG -- : Digest has changed!
I, [2019-01-02T13:37:33.111993 #28588]  INFO -- : Generating Template for nginx.conf...
I, [2019-01-02T13:37:33.112836 #28588]  INFO -- : New template written for nginx.conf!
I, [2019-01-02T13:37:33.112876 #28588]  INFO -- : Executing Callback: systemctl reload nginx
I, [2019-01-02T13:37:33.119767 #28588]  INFO -- : Callback: pid 28590 exit 0
D, [2019-01-02T13:37:35.120054 #28588] DEBUG -- : Consul Service Check: http://consul.somedomain.com:8500/v1/health/service/someapp
D, [2019-01-02T13:37:35.123912 #28588] DEBUG -- : No Status Change for someapp
```
