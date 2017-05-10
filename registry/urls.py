# -*- coding: utf-8 -*-
from django.conf.urls import url
from . import views

urlpatterns = [
    url(r'^$', views.catalog, name='catalog'),
    url(r'^(?P<name>[a-z0-9_-]+)/$', views.registry, name='registry'),
]