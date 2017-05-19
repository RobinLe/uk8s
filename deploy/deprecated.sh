#!/bin/bash

# cluster name for the cluster
export CLUSTER_NAME=${CLUSTER_NAME:-default}

# IP address for k8s master server 
export MASTER_IP=${MASTER_IP:-0.0.0.0}

# service IP range of the cluster
export SERVICE_IP_RANGE=${SERVICE_IP_RANGE:-10.96.0.0/12}

# the first IP of the SERVICE_IP_RANGE
export CLUSTER_SERVICE_IP=${CLUSTER_SERVICE_IP:-10.96.0.1}

# IP address for a cluster DNS server
export DNS_SERVICE_IP=${DNS_SERVICE_IP:-10.96.0.10}

# kubernetes pod network range
export POD_NETWORK=${POD_NETWORK:-10.244.0.0/16}

# docker resgistry server
IMAGE_SERVER="192.168.18.250:5002/"
# docker image's name and version
KUBELET="k8s/kubelet:v1.5.1"
KUBE_PAUSE="k8s/pause:v3.0"
ETCD="k8s/etcd:v3.0.15"
KUBE_APISERVER="k8s/kube-apiserver:v1.5.1"
KUBE_CONTROLLER_MANAGER="k8s/kube-controller-manager:v1.5.1"
KUBE_SCHEDULER="k8s/kube-scheduler:v1.5.1"
KUBE_PROXY="k8s/kube-proxy:v1.5.1"
FLANNEL="k8s/flannel:v0.6.1-28-g5dde68d-amd64"
KUBE_DNS="k8s/kube-dns:1.9"
KUBE_DNSMASQ="k8s/kube-dnsmasq:1.4"
KUBE_DNSMASQ_METRICS="k8s/kube-dnsmasq-metrics:1.0"
EXECHEALTHZ="k8s/exechealthz:1.2"
KUBE_DASHBOARD="k8s/kube-dashboard:v1.5.1"

IMAGE_ARRAY=(
  $KUBELET
  $KUBE_PAUSE
  $ETCD
  $KUBE_APISERVER
  $KUBE_CONTROLLER_MANAGER
  $KUBE_SCHDULER
  $KUBE_PROXY
  $FLANNEL
  $KUBE_DNS
  $KUBE_DNSMASQ
  $KUBE_DNSMASQ_METRICS
  $EXECHEALTHZ
  $KUBE_DASHBOARD
)

CURRENT_DIR=$(dirname "${BASH_SOURCE}")
ROOT_DIR=$(dirname "../${BASH_SOURCE}")
CONF_DIR="/etc/kubernetes"
BIN_DIR="/usr/local/bin"

OS_RELEASE=$(cat /etc/*elease | grep ^ID=)
OS_VERSION=$(cat /etc/*elease | grep VERSION_ID)

function stop_firewall() {
  echo -e "\033[42;37m+ Stopping filewall... \033[0m"
  ufw disable >/dev/null 2>&1 || true
  systemctl disable firewalld >/dev/null 2>&1 || true
  systemctl stop firewalld >/dev/null 2>&1 || true
  echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
  echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf
  /sbin/sysctl -p > /dev/null
  /sbin/sysctl -w net.ipv4.route.flush=1 > /dev/null
}



function init_env() {
  echo -e "\033[42;37m+ Prepare kubernetes environment. \033[0m"
  ip link set cni0 down 2> /dev/null && ip link delete cni0 type bridge
  ip link set flannel.1 down 2> /dev/null && ip link delete flannel.1 type bridge
  docker ps -a | grep kubelet | awk '{print $1}' | xargs docker rm --force 2> /dev/null || true
  docker rm -f $(docker ps -a --format={{.ID}}) 2> /dev/null || true
  p=`cat /proc/mounts | awk '{print $2}' | grep '/var/lib/kubelet/' | xargs`
  if [ ! -z "$p" ];then umount $p;fi
  p=`cat /proc/mounts | awk '{print $2}' | grep '/var/lib/kubelet' | xargs`
  if [ ! -z "$p" ];then umount $p;fi
  rm -rf /etc/kubernetes /var/lib/cni /var/lib/kubelet /var/lib/etcd
  mkdir -p ${CONF_DIR}/pki ${CONF_DIR}/manifests ${CONF_DIR}/addons
  mkdir -p /opt/cni/bin /var/lib/kubelet
  mount --bind /var/lib/kubelet /var/lib/kubelet
  mount --make-shared /var/lib/kubelet
  sed -i "2 i mount --bind /var/lib/kubelet /var/lib/kubelet" /etc/rc.local
  sed -i "3 i mount --make-shared /var/lib/kubelet" /etc/rc.local
}

function port_check() {
  netstat -antp | grep $1 | grep -i listen
  rc=$?
  if [ $rc -eq 0 ];then
    echo -e "\033[41;37m- Port $1 confict! \033[0m"
    contact
    exit 1
  fi
}

function ports_check() {
  echo -e "\033[42;37m+ Port conflict checking. \033[0m"
  port_check 2379
  port_check 8080
  port_check 6443
  port_check 10250
  port_check 10251
  port_check 10252
}

function config_dockerd() {
  echo -e "\033[42;37m+ Restart docker service. \033[0m"
  cat /lib/systemd/system/docker.service | grep MountFlags > /dev/null
  rc=$?
  if [ $rc -eq 0 ];then
    sed -i "s/MountFlags=slave/MountFlags=/g" /lib/systemd/system/docker.service
  else
    sed -i "s/\[Service\]/\[Service\]\nMountFlags=/g" /lib/systemd/system/docker.service
  fi
  systemctl daemon-reload || true
  systemctl restart docker || true
  service docker restart || true
  if [[ $? -ne 0 ]];then
    echo -e "\033[41;37m- Failed restart dockerd! \033[0m"
    contact
    exit 1
  fi
}

function get_files() {
  echo -e "\033[42;37m+ Download kubectl, cni and kubernetes conf files. \033[0m"
  wget -O /opt/cni/bin/cni-v0.3.1.tgz http://192.168.14.165/common/cni-v0.3.1.tgz -q
  if [[ $? -ne 0 ]];then
    echo -e "\033[41;37m- Failed download files! \033[0m"
    contact
    exit 1
  fi
  wget -O ${BIN_DIR}/kubectl-amd64-v1.5.1.tgz  http://192.168.14.165/common/kubectl-amd64-v1.5.1.tgz -q
  wget -O ${CONF_DIR}/configfiles.tgz http://192.168.14.165/common/configfiles.tgz -q
  wget -O ${CONF_DIR}/pki/ca.pem http://192.168.14.165/common/ca/ca.pem -q
  wget -O ${CONF_DIR}/pki/ca-key.pem http://192.168.14.165/common/ca/ca-key.pem -q
  tar -zxf /opt/cni/bin/cni-v0.3.1.tgz -C /opt/cni/bin/
  tar -zxf ${BIN_DIR}/kubectl-amd64-v1.5.1.tgz -C ${BIN_DIR}/
  tar -zxf ${CONF_DIR}/configfiles.tgz -C ${CONF_DIR}/
  cp ./ufleet.sh /etc/kubernetes/env.sh
}

function generate_certs() {
  echo -e "\033[42;37m+ Generate kubernetes certificates. \033[0m"
  # create openssl config
  cat << EOF > openssl.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = ${CLUSTER_SERVICE_IP}
IP.2 = ${MASTER_IP}
EOF
  # apiserver
  openssl genrsa -out apiserver-key.pem 2048 >/dev/null 2>&1
  openssl req \
    -new \
    -key apiserver-key.pem \
    -out apiserver.csr \
    -subj "/CN=kube-apiserver" \
    -config openssl.cnf >/dev/null 2>&1
  openssl x509 \
    -req \
    -in apiserver.csr \
    -CA ${CONF_DIR}/pki/ca.pem \
    -CAkey ${CONF_DIR}/pki/ca-key.pem \
    -CAcreateserial \
    -out apiserver.pem \
    -days 365 \
    -extensions v3_req \
    -extfile openssl.cnf >/dev/null 2>&1
  # admin
  openssl genrsa -out admin-key.pem 2048 >/dev/null 2>&1
  openssl req \
    -new \
    -key admin-key.pem \
    -out admin.csr \
    -subj "/CN=kube-admin" >/dev/null 2>&1
  openssl x509 \
    -req \
    -in admin.csr \
    -CA ${CONF_DIR}/pki/ca.pem \
    -CAkey ${CONF_DIR}/pki/ca-key.pem \
    -CAcreateserial \
    -out admin.pem \
    -days 365 >/dev/null 2>&1
  mv *.pem *.csr openssl.cnf ${CONF_DIR}/pki
}

function generate_tokens() {
  echo -e "\033[42;37m+ Generate kubernetes tokens file. \033[0m"
  echo "admin,admin,admin" > /etc/kubernetes/pki/tokens.csv
}

function generate_cluster_conf() {
  echo -e "\033[42;37m+ Prepare components config files. \033[0m"
  # replace the image's name in every yaml config file
  sed -i "s/image-etcd/$(echo ${IMAGE_SERVER}$ETCD | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/manifests/etcd.yaml
  sed -i "s/image-apiserver/$(echo ${IMAGE_SERVER}$KUBE_APISERVER | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/manifests/kube-apiserver.yaml
  sed -i "s/image-scheduler/$(echo ${IMAGE_SERVER}$KUBE_SCHEDULER | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/manifests/kube-scheduler.yaml
  sed -i "s/image-controller-manager/$(echo ${IMAGE_SERVER}$KUBE_CONTROLLER_MANAGER | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/manifests/kube-controller-manager.yaml
  sed -i "s/image-flannel/$(echo ${IMAGE_SERVER}$FLANNEL | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/flannel.yaml
  sed -i "s/image-kubeproxy/$(echo ${IMAGE_SERVER}$KUBE_PROXY | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/kube-proxy.yaml
  sed -i "s/image-dns/$(echo ${IMAGE_SERVER}$KUBE_DNS | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/kube-dns.yaml
  sed -i "s/image-masq/$(echo ${IMAGE_SERVER}$KUBE_DNSMASQ | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/kube-dns.yaml
  sed -i "s/image-metrics/$(echo ${IMAGE_SERVER}$KUBE_DNSMASQ_METRICS | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/kube-dns.yaml
  sed -i "s/image-exechealthz/$(echo ${IMAGE_SERVER}$EXECHEALTHZ | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/kube-dns.yaml
  sed -i "s/image-dashboard/$(echo ${IMAGE_SERVER}$KUBE_DASHBOARD | sed -e 's/\//\\\//g')/g" ${CONF_DIR}/addons/kube-dashboard.yaml
  
  # set cluster name
  sed -i "s/cluster_name/${CLUSTER_NAME}/g" ${CONF_DIR}/kubelet.conf
  # set master ip
  sed -i "s/replace_masterip/${MASTER_IP}/g" ${CONF_DIR}/manifests/kube-apiserver.yaml
  sed -i "s/replace_masterip/${MASTER_IP}/g" ${CONF_DIR}/kubelet.conf
  # set pod network
  POD_NETWORK=${POD_NETWORK////\\/}
  sed -i "s/pod_network/${POD_NETWORK}/g" ${CONF_DIR}/manifests/kube-controller-manager.yaml
  sed -i "s/pod_network/${POD_NETWORK}/g" ${CONF_DIR}/addons/flannel.yaml
  # set service ip range
  SERVICE_IP_RANGE=${SERVICE_IP_RANGE////\\/}
  sed -i "s/service_ip_range/${SERVICE_IP_RANGE}/g" ${CONF_DIR}/manifests/kube-apiserver.yaml

  mkdir -p ~/.kube
  cp /etc/kubernetes/kubelet.conf ~/.kube/config
}

function install_images() {
  echo -e "\033[42;37m+ Load components docker images. \033[0m"
  for image in ${IMAGE_ARRAY[*]}
  do
    docker pull ${IMAGE_SERVER}${image}
    if [[ $? -ne 0 ]];then
      echo -e "\033[41;37m- Failed pull images! \033[0m"
      contact
      exit 1
    fi
  done
}

function container_check() {
  n=1
  while :
  do
    n=$(( n+1 ))
    docker ps --filter status=running | grep $1 > /dev/null
    rc=$?
    if [ $rc -eq 0 ];then
      echo -e "\033[42;37m+ $1 is running  \033[0m"
      break
    elif [ $n -ge 5 ];then
      echo -e "\033[41;37m- Failed to start $1. \033[0m"
      contact
      exit 1
    else
      echo -ne "\033[43;37m+ Waiting for $1 up. \033[0m\r"
      sleep 10
    fi
  done
}

function pod_check() {
  while :
  do
    status=$(kubectl get pods --all-namespaces | grep $1 | awk '{print $4}')
    restart=$(kubectl get pods --all-namespaces | grep $1 | awk '{print $5}')
    if [ -z $restart ];then
      sleep 5
      continue
    elif [ -z $status ];then
      sleep 5
      continue
    elif [ $status == "Running" ];then
      # echo -e "\033[42;37m+ pod $1 is running  \033[0m"
      break
    elif [ $status == "ContainerCreating" ];then
      continue
      # echo -ne "\033[43;37m+ Waiting for $1 up. \033[0m\r"
    elif [ $restart -ge 5 ];then
      echo -e "\033[41;37m- Failed to start pod $1. \033[0m"
      contact
      exit 1
    fi
  done
}

function start_kubernetes() {
  echo -e "\033[42;37m+ Starting kubernetes. \033[0m"
  docker run -d \
    --name=k8s-kubelet \
    --restart=always \
    --net=host \
    --pid=host \
    --privileged \
    -v /sys:/sys:ro \
    -v /var/run:/var/run:rw \
    -v /var/lib/docker/:/var/lib/docker:rw \
    -v /var/lib/kubelet/:/var/lib/kubelet:shared \
    -v /var/lib/etcd/:/var/lib/etcd:rw \
    -v /var/lib/cni/:/var/lib/cni:rw \
    -v /etc/cni/net.d/:/etc/cni/net.d/:rw \
    -v /opt/cni/bin/:/opt/cni/bin/:rw \
    -v /etc/kubernetes/:/etc/kubernetes/:rw \
    ${IMAGE_SERVER}${KUBELET} \
    nsenter --target=1 --mount --wd=. -- ./usr/bin/kubelet \
      --kubeconfig=/etc/kubernetes/kubelet.conf \
      --require-kubeconfig=true\
      --pod-manifest-path=/etc/kubernetes/manifests \
      --pod-infra-container-image=${IMAGE_SERVER}${KUBE_PAUSE} \
      --allow-privileged=true \
      --network-plugin=cni \
      --cni-conf-dir=/etc/cni/net.d \
      --cni-bin-dir=/opt/cni/bin \
      --cluster-dns=${DNS_SERVICE_IP} \
      --cluster-domain=cluster.local
  #progress 1.5
  sleep 60
  container_check kubelet
  #pod_check etcd
  #pod_check apiserver
  #pod_check controller-manager
  #pod_check scheduler
}

function install_addons() {
  echo -e "\033[42;37m+ Install enssial addons. \033[0m"
  ${BIN_DIR}/kubectl create -f ${CONF_DIR}/addons/flannel.yaml
  pod_check flannel
  ${BIN_DIR}/kubectl create -f ${CONF_DIR}/addons/kube-proxy.yaml
  pod_check kube-proxy
  ${BIN_DIR}/kubectl create -f ${CONF_DIR}/addons/kube-dns.yaml
  pod_check kube-dns
  ${BIN_DIR}/kubectl create -f ${CONF_DIR}/addons/kube-dashboard.yaml
  pod_check dashboard
  #${BIN_DIR}/kubectl create -f ${CONF_DIR}/addons/ufleet.yaml
  #ufleet_detect
}

function default() {
  #sed -i "s/10.96.0.0\\/12/$SERVICE_IP_RANGE/g" /etc/kubernetes/env.sh
  #sed -i "s/10.96.0.1/$CLUSTER_SERVICE_IP/g" /etc/kubernetes/env.sh
  #sed -i "s/10.96.0.10/$DNS_SERVICE_IP/g" /etc/kubernetes/env.sh
  #sed -i "s/10.244.0.0\\/16/$POD_NETWORK/g" /etc/kubernetes/env.sh
  sed -i "s/0.0.0.0/$MASTER_IP/g" /etc/kubernetes/env.sh
}

function ufleet_detect() {
  while :
  do
    status=$(kubectl get pods --namespace=ufleet | grep ufleet-project | awk '{print $3}')
    restart=$(kubectl get pods --namespace=ufleet | grep ufleet-project | awk '{print $4}')
    if [ $status == "Running" ];then
      echo -e "\033[42;37m+ Ufleet is running at http://${MASTER_IP}:32000 \033[0m"
      exit 0
    elif [ $status == "ContainerCreating" ];then
      echo -ne "\033[43;37m+ Waiting for Ufleet up. \033[0m\r"
    elif [ $restart -ge 5 ];then
      echo -e "\033[41;37m- Failed to start Ufleet. \033[0m"
      contact
      exit 1
    fi
  done
}

function progress() {
  b=''
  for ((i=0;$i<=100;i+=2))
  do
    printf "progress:[%-50s]%d%%\r" $b $i
    sleep $1
    b=#$b  
  done
  echo 
}

function contact() {
  echo -e "\033[45;37mPlease contact http://www.youruncloud.com for help! \033[0m"
}

function run() {
  stop_firewall
  initenv
  ports_check
  config_dockerd
  get_files
  generate_certs
  generate_tokens
  generate_cluster_conf
  install_images
  default
  start_kubernetes
  install_addons
  #kubectl taint nodes $(hostname) dedicated=kube-system:NoSchedule
}

function usage() {
  echo -e "Usage: $0 [-u ufleet_ip] [-s service_ip_range] [-p pod_ip_range] \n
  eg：./ufleet.sh -u 192.168.0.180 \n
  -u  the host ip of ufleet" 1>&2; exit 1;
}

while getopts ":u:" o; do
  case "${o}" in
    u)
      u=${OPTARG}
      ;;
    *)
      usage
      ;;
  esac
done
#shift $((OPTIND-1))

if [ -z "${u}" ]; then
  usage
fi
MASTER_IP=${u}

run

