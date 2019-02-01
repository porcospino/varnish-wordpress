# VCL for Varnish Enterprise 6.0 in AWS

99.9% robbed from https://github.com/admingeekz/varnish-wordpress

## Best used in Cloudformation

You will need an AMI running [Varnish Enterprise 6](https://aws.amazon.com/marketplace/pp/B07L7HVVMF).
This comes with [`vmod_goto`](https://docs.varnish-software.com/varnish-cache-plus/vmods/goto/), 
which will allow your Varnish cache to connect to a dynamic backend, such as an 
[Application Load Balancer](https://aws.amazon.com/elasticloadbalancing/).  You can use this to front 
an auto-scaling group stuffed with (stateless) Wordpress servers.

You'll also need a [Launch Configuration](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-as-launchconfig.html) 
which replaces the string `{{ALB_HOSTNAME}}` with the DNS name of the load balancer fronting your Wordpress ASG.

Consider the following architecture:

```
          +------------------------------+
0         |   Application load balancer  |
          +------------------------------+
                         |
          +------------------------------+
1         |  Varnish auto-scaling group  |
          +------------------------------+
                         |
          +------------------------------+
2         |   Application load balancer  |
          +------------------------------+
                         |
          +------------------------------+
3         | Wordpress auto-scaling group |
          +------------------------------+
```

The Varnish auto-scaling group will need to be configured to accept traffic from the listener at 0, 
and to forward traffic to the listener at 2, so each instance will need to launch with a configuration 
like the following:

```
"VarnishLaunchConfig": {
  "Type" : "AWS::AutoScaling::LaunchConfiguration",
  "Metadata" : {
    "AWS::CloudFormation::Init" : {
      "configSets" : {
        "varnish_install" : ["configure_varnish"]
      },
      "configure_varnish" : {
        "files" : {
          "/etc/varnish/default.vcl" : {
            "source"  : "https://raw.githubusercontent.com/porcospino/varnish-wordpress/master/default.vcl",
            "context" : { "ALB_HOSTNAME"  :  { "Fn::GetAtt" : [ "PrivateLoadBalancer", "DNSName" ] } },
          }
        },
        "commands" : {
          "01enable_varnish" : {
            "command" : "systemctl enable varnish.service"
          },
          "02restart_varnish" : {
            "command" : "systemctl restart varnish.service"
          }
        }
      }
    }
  }
},
"PrivateLoadBalancer" : {
  "Type" : "AWS::ElasticLoadBalancingV2::LoadBalancer",
  "Properties" : {
    "Scheme": "internal"
    [ ... ]
```
