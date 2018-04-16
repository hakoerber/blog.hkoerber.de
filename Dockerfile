FROM nginx:1.12.2-alpine

ADD _site/ /usr/share/nginx/html/
