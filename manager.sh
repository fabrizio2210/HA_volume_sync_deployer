#!/bin/bash

set -x 
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

# NAMES
# server: volume-sync-server
# proxy: volume-sync-proxy-$NAME

proxyServicePrefix="volume-sync-proxy-"
serverServiceName="volume-sync-server"
volumePrefix="/opt/data"
servicePort=80

nodeName=$VOLUMESYNC_NAME
key=$VOLUMESYNC_KEY
volumesString=$VOLUMESYNC_VOLUMES
auth=$VOLUMESYNC_AUTH
serverImage=$VOLUMESYNC_SERVERIMAGE
proxyImage=$VOLUMESYNC_PROXYIMAGE
stack=$VOLUMESYNC_STACK
serviceName=$VOLUMESYNC_SERVICE
servicePort=$VOLUMESYNC_PORT
traefikNetwork=$VOLUMESYNC_TRAEFIKNETWORK

while getopts ":n:k:d:a:i:c:s:r:p:t:" opt; do
  case $opt in
		n)
			nodeName=$(echo $OPTARG | tr -d '[[:space:]]')
			;;
		k)
			key=$(echo $OPTARG | tr -d '[[:space:]]')
			;;
		d)
			volumesString=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		a)
			auth=$OPTARG
      ;;
		i)
			serverImage=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		c)
			proxyImage=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		s)
			stack=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		r)
			serviceName=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		p)
			servicePort=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
		t)
			traefikNetwork=$(echo $OPTARG | tr -d '[[:space:]]')
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

[ -z "$nodeName" ] && echo "Node name missing, define with -n" && exit 1
[ -z "$key" ] && echo "Key is missing, define with -k" && exit 1
[ -z "$volumesString" ] && echo "Dirs is missing, define with -d" && exit 1
[ -z "$auth" ] && echo "Auth is missing, define with -a" && exit 1
[ -z "$serverImage" ] && echo "Server image is missing, define with -i" && exit 1
[ -z "$proxyImage" ] && echo "Client image is missing, define with -c" && exit 1
[ -z "$serviceName" ] && echo "Service name is missing, define with -r" && exit 1
[ -z "$traefikNetwork" ] && echo "Traefik network name is missing, define with -t" && exit 1


# sanitize node name
nodeName=$(echo $nodeName| tr -d '.')
nodeName=$(echo $nodeName| tr -d '_')
nodeName=$(echo $nodeName| tr -d '-')

######
# MAIN

###
# Retrieve the state to be of the cluster from external
# take list of nodes from TXT in DNS domain.
# Key="nodes" Value separate  by ","

# compute the mount volumes to be synced and pass the list inside the container
mountOpt=
internalDirs=
i=1
for dir in $(echo $volumesString | tr ',' '\n') ; do
  mountOpt="$mountOpt --mount type=volume,source=$dir,destination=$volumePrefix$i"
  internalDirs="$internalDirs$volumePrefix$i,"
  let i=$i+1
done
internalDirs=${internalDirs::-1}

# persisting csync2 data
mountOpt="$mountOpt --mount type=volume,source=etc_csync2,destination=/etc"
mountOpt="$mountOpt --mount type=volume,source=var_csync2,destination=/var/lib/csync2"


while true ; do 
  nodeList=$(for _string in $(dig TXT $serviceName +short | grep nodes=) ; do 
    echo ${_string#*=}|tr -d '"' | tr ',' '\n' 
  done)
  
  # compute nodelist for the server
  serverNodeList=
  for _node in $nodeList ; do
    serverNodeList="$serverNodeList${_node%@*}@${stack}_${proxyServicePrefix}${_node%@*} "
  done
  serverNodeList=${serverNodeList::-1}
  ###
  # Localize stack
  # Either take from argument or looking my container
  if [ -z "$stack" ] ; then
    for _container in $(docker ps --format '{{printf "%s;%s" .ID .Labels}}' | tr -d ' ') ; do
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
  # Verify services of stack and destroy/deploy if differs from state to be
  
  changed=0
  existingClientServices=$(docker service ls -q --filter "label=com.docker.stack.namespace=$stack" --filter "name=$proxyServicePrefix")
  for _node in $nodeList ; do
    if [ ${_node%@*} == $nodeName ] ; then
      # no need for a proxy for the local node
      continue
    fi
    _nodeID=$(docker service ls -q --filter "label=com.docker.stack.namespace=$stack" --filter "name=$proxyServicePrefix${_node%@*}")
    if [ -z "$_nodeID" ] ; then
      changed=1
      # deploy client service
      docker service create --name "$proxyServicePrefix${_node%@*}" \
                            --label  com.docker.stack.image="$proxyImage" \
                            --label   com.docker.stack.namespace="$stack" \
                            --container-label com.docker.stack.namespace="$stack" \
                            --no-resolve-image \
                            --network name=$traefikNetwork,alias=${stack}_$proxyServicePrefix${_node%@*}  \
                            $proxyImage /usr/local/bin/chisel client --auth $auth http://${_node#*@}:$servicePort 0.0.0.0:30865:localhost:30865
    else 
      # remove from existing to verify that there is no services remaining
      existingClientServices=$(echo $existingClientServices | tr ' ' '\n' | grep -v $_nodeID)
    fi
  done
  
  if [ ! -z "$existingClientServices" ] ; then
    # destroy supplementary services
    changed=1
    for _service in $existingClientServices ; do
      docker service rm $_service
    done
  fi
  
  if [ -z "$(docker service ls -q --filter "label=com.docker.stack.namespace=$stack" --filter "name=$serverServiceName")" ] ; then
    # server is missing
    changed=1
  fi
  
  if [ $changed -eq 1 ] ; then
    # destroy and deploy server service
      docker service rm $(docker service ls -q --filter "label=com.docker.stack.namespace=$stack" --filter "name=$serverServiceName")
      docker service create --name "$serverServiceName" \
                            --label  com.docker.stack.image="$serverImage" \
                            --label  com.docker.stack.namespace="$stack" \
                            --label  traefik.frontend.rule="Host: $nodeName.$serviceName" \
                            --label  traefik.port="80" \
                            --container-label com.docker.stack.namespace="$stack" \
                            --no-resolve-image \
                            --env CSYNC2_NODES=$(echo $serverNodeList | tr '\n' ',' | tr ' ' ',') \
                            --env CSYNC2_NAME=$nodeName \
                            --env CSYNC2_KEY=$key \
                            --env CSYNC2_DIRS=$internalDirs \
                            --env CSYNC2_AUTHJSON="{ \"$auth\": [\"\"] }" \
                            --network $traefikNetwork  \
                            $mountOpt \
                            $serverImage
  fi

  sleep 30

done
