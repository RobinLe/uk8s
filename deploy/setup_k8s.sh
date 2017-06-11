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

# kubernetes配置文件目录
CONF_DIR="/etc/kubernetes"
BIN_DIR="/usr/local/bin"

# 下载kubernetes
function download_kubernetes() {
	echo -e "\033[42;37m+ 下载kubernetes安装文件. \033[0m"
	docker pull uk8s.com/google-containers/hyperkube-amd64:v1.5.0
	docker pull uk8s.com/google-containers/pause-amd64:3.0
	docker pull uk8s.com/coreos/etcd:v3.0.15
	if [[ $? -ne 0 ]]; then
		echo -e "\033[41;37m- 拉取镜像失败! \033[0m"
		exit 1
	fi
	# 下载cni二进制文件，kubectl二进制文件
	wget -O /opt/cni/bin/cni-v0.3.1.tgz https://uk8s.com/cni-v0.3.1.tgz -q
	wget -O /usr/local/bin/kubectl-amd64-v1.5.1.tgz https://uk8s.com/kubectl-amd64-v1.5.1.tgz -q
	tar -zxf /opt/cni/bin/cni-v0.3.1.tgz -C /opt/cni/bin/
	tar -zxf /usr/local/bin/kubectl-amd64-v1.5.1.tgz -C /usr/local/bin
}

# 初始化kubernetes安装环境
function init_kube_env() {
	echo -e "\033[42;37m+ 初始化安装环境. \033[0m"
	clean_kube_env
	create_kube_dir
	check_kube_ports_status
}

# 清除kubernetes环境
function clean_kube_env() {
	delete_kube_container
	delete_net_bridge
	umount_kube_dir
}

# 删除kubernetes容器
function delete_kube_container() {
	docker ps -a | grep kube | awk '{print $1}' | xargs docker rm --force || true
}

# 删除kubernetes创建的cni/flannel虚拟网桥
function delete_net_bridge() {
	ip link set cni0 down 2>/dev/null
	ip link delete cni0 type bridge
	ip link set flannel.1 down 2>/dev/null
	ip link delete flannel.1 type bridge
}

# 卸载删除kubernetes目录
function umount_kube_dir() {
	p=$(cat /proc/mounts | awk '{print $2}' | grep '/var/lib/kubelet/' | xargs)
	if [ ! -z "$p" ]; then
		umount $p
	fi
	p=$(cat /proc/mounts | awk '{print $2}' | grep '/var/lib/kubelet' | xargs)
	if [ ! -z "$p" ]; then
		umount $p
	fi
	rm -rf /var/lib/cni /var/lib/kubelet /var/lib/etcd /opt/cni ${CONF_DIR}/
}

# 创建kubernetes目录
function create_kube_dir() {
	mkdir -p ${CONF_DIR}/pki ${CONF_DIR}/manifests ${CONF_DIR}/addons
	mkdir -p /opt/cni/bin /var/lib/kubelet
	mount --bind /var/lib/kubelet /var/lib/kubelet
	mount --make-shared /var/lib/kubelet
	# 重启自动挂载（ubuntu14.04 bug）
	sed -i "2 i mount --bind /var/lib/kubelet /var/lib/kubelet" /etc/rc.local
	sed -i "3 i mount --make-shared /var/lib/kubelet" /etc/rc.local
}

# 端口占用检查
function check_port_status() {
	netstat -antp | grep $1 | grep -i listen
	rc=$?
	if [ $rc -eq 0 ]; then
		echo -e "\033[41;37m- Port $1 confict! \033[0m"
		exit 1
	fi
}

# kubernetes端口占用检查
function check_kube_ports_status() {
	echo -e "\033[42;37m+ 端口冲突检测. \033[0m"
	check_port_status 2379
	check_port_status 8080
	check_port_status 6443
	check_port_status 10250
	check_port_status 10251
	check_port_status 10252
}

# 创建kubernetes证书
function generate_kube_certs() {
	echo -e "\033[42;37m+ Generate kubernetes certificates. \033[0m"
	# 创建CA根证书
	openssl req -newkey rsa:2048 \
		-nodes -sha256 -keyout ca.key -x509 -days 365 \
		-out ca.pem \
		-subj /CN=kubernetes
	# 创建openssl配置
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
	# 创建apiserver证书
	openssl genrsa -out apiserver-key.pem 2048 >/dev/null 2>&1
	openssl req -new -key apiserver-key.pem \
		-out apiserver.csr \
		-subj "/CN=kube-apiserver" \
		-config openssl.cnf >/dev/null 2>&1
	openssl x509 -req -in apiserver.csr \
		-CA ca.pem \-CAkey ca.key -CAcreateserial \
		-out apiserver.pem \
		-days 365 -extensions v3_req \
		-extfile openssl.cnf >/dev/null 2>&1
	mv *.pem *.csr *.key openssl.cnf ${CONF_DIR}/pki
}

# 创建kubernetes配置文件
function generate_kube_config() {
	wget -O /etc/kubernetes/manifests/etcd.yaml https://uk8s.com/yaml/etcd.yaml -q
	wget -O /etc/kubernetes/manifests/kube-apiserver.yaml https://uk8s.com/yaml/kube-apiserver.yaml -q
	wget -O /etc/kubernetes/manifests/kube-scheduler.yaml https://uk8s.com/yaml/kube-scheduler.yaml -q
	wget -O /etc/kubernetes/manifests/kube-controller-manager.yaml https://uk8s.com/yaml/kube-controller-manager.yaml -q
	cat << EOF > /etc/kubernetes/kubelet.conf
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.pem
    server: https://${MASTER_IP}:6443
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: admin
  name: admin@${CLUSTER_NAME}
- context:
    cluster: ${CLUSTER_NAME}
    user: kubelet
  name: kubelet@${CLUSTER_NAME}
current-context: admin@${CLUSTER_NAME}
kind: Config
preferences: {}
users:
- name: admin
  user:
    client-certificate: /etc/kubernetes/pki/apiserver.pem
    client-key: /etc/kubernetes/pki/apiserver-key.pem
- name: kubelet
  user:
    client-certificate: /etc/kubernetes/pki/apiserver.pem
    client-key: /etc/kubernetes/pki/apiserver-key.pem
EOF
}

# 配置dockerd，修改MountFlags参数
function config_dockerd() {
	echo -e "\033[42;37m+ Restart docker service. \033[0m"
	cat /lib/systemd/system/docker.service | grep MountFlags >/dev/null
	rc=$?
	if [ $rc -eq 0 ]; then
		sed -i "s/MountFlags=slave/MountFlags=/g" /lib/systemd/system/docker.service
	else
		sed -i "s/\[Service\]/\[Service\]\nMountFlags=/g" /lib/systemd/system/docker.service
	fi
	systemctl daemon-reload || true
	systemctl restart docker || true
	service docker restart || true
	if [[ $? -ne 0 ]]; then
		echo -e "\033[41;37m- Failed restart dockerd! \033[0m"
		contact
		exit 1
	fi
}

# 关闭防火墙Firewall
function stop_firewall() {
	echo -e "\033[42;37m+ 关闭主机防火墙 \033[0m"
	# centos
	systemctl disable firewalld >/dev/null 2>&1 || true
	systemctl stop firewalld >/dev/null 2>&1 || true
	# ubuntu
	ufw disable >/dev/null 2>&1 || true
	# fix kube-dns bug
	echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
	echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf
	/sbin/sysctl -p > /dev/null
	/sbin/sysctl -w net.ipv4.route.flush=1 > /dev/null
}

# 启动kubelet
function run_kubelet() {
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
		uk8s.com/google-containers/hyperkube-amd64:v1.5.0 \
		./kubelet \
		--kubeconfig=/etc/kubernetes/kubelet.conf \
		--require-kubeconfig=true\
		--pod-manifest-path=/etc/kubernetes/manifests \
		--pod-infra-container-image=uk8s.com/google-containers/pause-amd64:3.0 \
		--allow-privileged=true \
		--network-plugin=cni \
		--cni-conf-dir=/etc/cni/net.d \
		--cni-bin-dir=/opt/cni/bin \
		--cluster-dns=${DNS_SERVICE_IP} \
		--cluster-domain=cluster.local
	sleep 60
}

# 启动kubernetes
function run_kubernetes() {
	download_kubernetes
	init_kube_env
	config_dockerd
	generate_kube_certs
	generate_kube_config
	run_kubelet
	stop_firewall
}