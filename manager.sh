#!/bin/bash

# Goals:
# - keep the sync server up to date when the nodes are changed
# - keep the sync proxy up to date when the nodes are changed

# Input:
# (n) node name (localhost)
# (k) Csync2 key
# (d) directorie: list of directories to sync
# (a) proxy authorization: string of user paswword to authenticate proxy
# (i) server image to deploy: docker image to deploy for the server
# (c) proxy client image to deploy: docker image to deploy for client proxy
#

# from DNS
# ??port of the service??
# list of nodes (name@fqdn:port)


nodeName=$VOLUMESYNC_NODES
key=$VOLUMESYNC_KEY
dirsString=$VOLUMESYNC_DIRS
authJson=$VOLUMESYNC_AUTHJSON
serverImage=$VOLUMESYNC_SERVERIMAGE
clientImage=$VOLUMESYNC_CLIENTIMAGE
stack=$VOLUMESYNC_STACK
serviceName=$VOLUMESYNC_SERVICE

while getopts ":n:k:d:a:i:c:s:r:" opt; do
  case $opt in
		n)
			nodeName=$(echo $OPTARG | tr -d '[[:space:]]')
			;;
		k)
			key=$(echo $OPTARG | tr -d '[[:space:]]')
			;;
		d)
			dirsString=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		a)
			authJson=$OPTARG
      ;;
		i)
			serverImage=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		c)
			clientImage=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		s)
			stack=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		r)
			serviceName=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

[ -z "$nodeName" ] && echo "Node name missing, define with -n" && exit 1
[ -z "$key" ] && echo "Key is missing, define with -k" && exit 1
[ -z "$dirsString" ] && echo "Dirs is missing, define with -d" && exit 1
[ -z "$authJson" ] && echo "Auth json is missing, define with -a" && exit 1
[ -z "$serverImage" ] && echo "Server image is missing, define with -i" && exit 1
[ -z "$clientImage" ] && echo "Client image is missing, define with -c" && exit 1
[ -z "$serviceName" ] && echo "Service name is missing, define with -r" && exit 1



######
# MAIN

###
# Retrieve the state to be of the cluster from external
# take list of nodes from TXT in DNS domain.
# Key="nodes" Value separate  by ","

nodeList=$(for _string in $(dig TXT $serviceName +short | grep nodes=) ; do 
  echo ${_string#*=}|tr -d '"' | tr ',' '\n' 
done)

###
# Localizate stack
# or take from argument or looking my container
if [ -z "$stack" ] ; then
  for _container in $( docker ps --format '{{printf "%s;%s" .ID .Labels}}' | tr -d ' ') ; do
    if [ "${_container%;*}" == $(hostname -s) ] ; then
      for _label in $(echo ${_cont#*;} | tr ',' '\n') ; do
        if echo $_label | grep -q 'com.docker.swarm.service.name' ; then
          stack=${_label#*=}
        fi
      done
    fi
  done
fi

###
# Verify services of stack

###
# Deploy/destroy services if differs from state to be


