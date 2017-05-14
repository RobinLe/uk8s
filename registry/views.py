# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import json
from django.shortcuts import render

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

REGISTRY_BASE = "https://192.168.0.105:5000/v2"

def req(url, headers=None):
    """parser response of request to json format
    """
    if headers is None:
        headers = {}
    response = requests.get(url, verify=False, headers=headers)
    if response.status_code == 200:
        response = json.loads(response.text)
        return response
    return None

def get_registries():
    """get docker registry list
    """
    url = "/".join([REGISTRY_BASE, "_catalog"])
    response = req(url)
    if response is not None:
        return response["repositories"]
    return []

def get_images(name):
    """get all images of the registry
    """
    url = "/".join([REGISTRY_BASE, name, "/tags/list"])
    response = req(url)
    image_list = []
    if response is not None:
        headers = {"Accept": "application/vnd.docker.distribution.manifest.v2+json"}
        tags = response["tags"]
        for tag in tags:
            url = "/".join([REGISTRY_BASE, name, "/manifests", tag])
            response = req(url, headers)
            if response is not None:
                image = {}
                image["size"] = response["config"]["size"]
                for i in response["layers"]:
                    image["size"] += i["size"]
                image["size"] = round(float(image["size"]) / 1024 / 1024, 2)
                image["id"] = response["config"]["digest"][7:19]
                image["tag"] = tag
                image_list.append(image)
    return image_list

def registry(request):
    """render docker registry list page
    """
    return render(request, 'registry.html', {"registries": get_registries()})

def images(request, name):
    """render docker images list page
    """
    return render(request, 'images.html', {"images": get_images(name)})

def index(request):
    """render index page
    """
    return render(request, 'index.html')
