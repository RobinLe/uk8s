# nginx
docker run --name nginx -d \
  -p 443:443 \
  -p 80:80 \
  -v /root/certs:/etc/nginx/certs \
  -v /root/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:latest


# registry
docker run --name registry -d \
  -p 5000:5000 \
  --restart=always \
  -v /opt/registry:/var/lib/registry \
  -v /root/certs:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/uk8s.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/uk8s.key \
  registry:2

docker run -d -p 5000:5000 --restart=always --name registry \
  -v /root/config.yml:/etc/docker/registry/config.yml \
  -v /root/certs:/certs \
  -v /opt/registry:/var/lib/registry \
  registry:2


# certs
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -days 365 -out ca.pem
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.crt -days 365

openssl req -newkey rsa:4096 -nodes -sha256 -keyout server.key -x509 -days 365 -out server.crt -subj /CN=uk8s.com
cp certs/server.crt /etc/docker/certs.d/uk8s.com/ca.crt