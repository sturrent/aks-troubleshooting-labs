# AKS troubleshooting labs

This is a set of scripts and tools use to generate a docker image that will have the akslabs binary used to deploy AKS troubleshooting exercises.

It uses the shc_script_converter.sh (build using the following tool https://github.com/neurobin/shc) to abstract the lab scripts on binary format and then the use the Dockerfile to pack everyting on a Ubuntu container with az cli and kubectl.

Any time the AKS lab scripts require an update the github actions can be use to trigger a new build and push of the updated image.
This will take care of building a new script binary as well as new docker image that will get pushed to the corresponding registry.
The actions will get triggered any time a new release gets published.

Here is the general usage for the image and akslabs tool:

Run in docker
```docker run -it sturrent/akslabs:latest```

akslab tool usage
```
$ akslabs -h
akslabs usage: akslabs -l <LAB#> -u <USER_ALIAS> [-v|--validate] [-r|--region] [-h|--help] [--version]

Here is the list of current labs available:

***************************************************************
*        1. Scale action failed (SP issues)
*        2. Cluster failed to delete
*        3. Cluster deployment failed
*        4. Cluster failed after upgrade
*        5. Cluster with nodes not ready
***************************************************************

"-l|--lab" Lab scenario to deploy (5 possible options)
"-r|--region" region to create the resources
"-u|--user" User alias to add on the lab name
"--version" print version of akslabs
"-h|--help" help info
```
