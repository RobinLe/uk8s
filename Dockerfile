FROM python:2.7

RUN pip install django
RUN pip install requests

WORKDIR /var/www/uk8s