# -*- coding: utf-8 -*-
from django.conf.urls import url
from . import views

urlpatterns = [
    url(r'^$', views.index, name='index'),
    url(r'^registry/$', views.registry, name='registry'),
    url(r'^registry/(?P<name>[a-z0-9_-]+)/$', views.images, name='images'),
]