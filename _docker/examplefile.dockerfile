FROM ubuntu:latest

RUN <<EOT bash
apt-get update && apt-get install nginx openssl -y
openssl ecparam -out root.key -name prime256v1 -genkey
openssl req -new -sha256 -key root.key -out root.csr -subj "/C=IN/ST=TL/L=HYD/O=myOrg/OU=IT/CN=example.com/emailAddress=hostmaster@example.com"
openssl x509 -req -sha256 -days 365 -in root.csr -signkey root.key -out root.crt
openssl ecparam -out server.key -name prime256v1 -genkey
openssl req -new -sha256 -key server.key -out server.csr -subj "/C=IN/ST=TL/L=HYD/O=myOrg/OU=IT/CN=www.example.com/emailAddress=hostmaster@example.com"
openssl x509 -req -in server.csr -CA root.crt -CAkey root.key -CAcreateserial -out server.crt -days 365 -sha256
cat server.crt >> bundle.crt && cat root.crt >> bundle.crt
mv server.key /etc/ssl/private/server.key
mv bundle.crt /etc/ssl/certs/bundle.crt
mkdir -p /var/www/www.example.com
touch /var/www/www.example.com/index.html
echo '<h1>Hello World!</h1>' >> /var/www/www.example.com/index.html
touch /var/log/nginx/nginx.vhost.access.log
touch /var/log/nginx/nginx.vhost.error.log
EOT

COPY example.conf /etc/nginx/sites-enabled/example.conf

EXPOSE 80
EXPOSE 443

STOPSIGNAL SIGQUIT

ENTRYPOINT ["nginx", "-g", "daemon off;"]
