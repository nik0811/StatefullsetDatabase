#!/bin/bash
set -e
function main 
{
      init "$@"
      package=("/usr/local/bin/helm" "/usr/local/bin/kind" )
      for i in ${package[@]}; do
            if [[ -x "$i" ]]; then
		    a=$(echo $i | cut -d '/' -f 5- | tr a-z A-Z) 
                    echo "$a Dependency Check Passed"
            else
                wget https://get.helm.sh/helm-v3.5.0-linux-amd64.tar.gz
                tar -xvzf helm-v3.5.0-linux-amd64.tar.gz
                sudo mv linux-amd64/helm /usr/local/bin/helm
                rm -rf helm-v3.5.0-linux-amd64.tar*
		            curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64
                chmod +x ./kind
                sudo mv ./kind /usr/local/bin/kind
            fi
      done    
      if [[ "$#" -eq 2 ]]; then
			    func=(create_kind_cluster nginx_ingress_kind set_mysql_passwd service_mysql deploy_mysql elasticsearch set_ingress_path patch_rolling_update)
          if [[ "$action" == "deploy" ]]; then
              for main_func in ${func[@]}; do
		         	  if [[ "$main_func" == "set_ingress_path" ]]; then
					    sleep_time
		         		    while true; do
		         			    a=$(kubectl get pods -n ingress-nginx | grep "Running" | awk '{printf $2}')
		         			    if [[ "$a" == "1/1" ]]; then
							    kill -9 $SPIN_PID
		         				    break 
		         			    else    
							    spin &
							    SPIN_PID=$!
							    trap "kill -9 $SPIN_PID" `seq 0 15`
		         			    fi
		         		    done
		         	  fi
		         	  echo ""
		         	  $main_func
		          done
			  trap "exit" INT TERM ERR
                          trap "kill 0" EXIT
          elif [[ "$action" == "destroy" ]]; then
              destroy_kind_cluster
          else
              usage
          fi
      fi
} 
function sleep_time 
{
  sleep 7
}
function  create_kind_cluster 
{   
    r=$(( $RANDOM % 10 ))
    cat <<EOF | kind create cluster --name kind-cluser-$r --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
}

function spin 
{
spinner="/ - \\ \| / - \\ \|"
  while :
  do
    for i in `seq 0 7`
    do
      echo -n "${spinner:$i:1}"
      echo -en "\010"
      sleep 1
    done
  done
}

function nginx_ingress_kind 
{
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
}

function set_mysql_passwd 
{
   a=$(echo -n Nikhil123 | base64)
   cat <<EOF | kubectl create -f -
   apiVersion: v1
   kind: Secret
   metadata:
      name: db-credentials
   type: Opaque
   data:
     mysql-password: $a
     mysql-root-password: $a
     mysql-user: $a
EOF
}

function service_mysql
{
     cat <<EOF | kubectl create -f -
     apiVersion: v1
     kind: Service
     metadata:
       name: mysql
       labels:
         app: mysql
     spec:
       ports:
       - port: 3306
         name: mysql
       selector:
         app: mysql
EOF
}

function deploy_mysql
{

   cat <<EOF | kubectl create -f -
   apiVersion: apps/v1
   kind: StatefulSet
   metadata:
     name: database
   spec:
     selector:
       matchLabels:
         app: mysql # has to match .spec.template.metadata.labels
     serviceName: "mysql"
     replicas: 5 # by default is 1
     template:
       metadata:
         labels:
           app: mysql # has to match .spec.selector.matchLabels
       spec:
         terminationGracePeriodSeconds: 10
         containers:
            - name: mysql
              image: mysql:5.7
              ports:
              - containerPort: 3306
                name: mysql
              volumeMounts:
              - name: "mysql"
                mountPath: "/var/lib/mysql"
                subPath: "mysql"
              env:
                - name: MYSQL_ROOT_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: mysql-root-password
     volumeClaimTemplates:
     - metadata:
         name: mysql
       spec:
          accessModes: [ "ReadWriteOnce" ]
          resources:
             requests:
               storage: 1Gi
EOF
}
	

function set_ingress_path
{
	cat <<EOF | kubectl create -f -
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: elastic
          annotations:
        spec:
          rules:
          - http:
              paths:
              - path: /elastic
                pathType: Prefix
                backend:
                    service:
                         name: elasticsearch-master
                         port: 
                           number: 9200
EOF
}

function elasticsearch 
{
   helm repo add elastic https://helm.elastic.co
   helm repo update
   helm install --name-template elasticsearch elastic/elasticsearch --set imageTag=7.10.1-SNAPSHOT --set replicas=1
}

function destroy_kind_cluster
{
	kind delete cluster --name $(kind get clusters)
}
function fix_docker_issue_affter_node_reboot
{
	sudo systemctl restart docker.service
}

function patch_rolling_update
{
   kubectl patch statefulset database -p '{"spec":{"updateStrategy":{"type":"RollingUpdate"}}}'
   kubectl patch statefulset database --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"mysql:latest"}]'
}

function usage
{
    cat <<EOF
    Usage:
        -h help
        -a action  #Value=deploy/destroy
    Example:
        ./efk.sh -a deploy/destroy
EOF
}

function init
{
action=""
while getopts h:a: option;
do 
	case "${option}" in
        h) usage "";exit 1
		;;
	a) action=$OPTARG
		;;
	\?) usage ""; exit 1
		;;
        esac
done
}
main "$@"
