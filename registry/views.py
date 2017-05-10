# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import json
from django.shortcuts import render

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)


def req(url):
    """parser response of request to json format
    """
    response = requests.get(url, verify=False)
    if response.status_code == 200:
        response = json.loads(response.text)
        return response
    return None


def catalog(request):
    """get registry catalog
    """
    url = "https://192.168.3.110:5000/v2/_catalog"
    response = req(url)
    if response is not None:
        context = {'catalog': response["repositories"]}
        return render(request, 'catalog.html', context)
    return render(request, 'catalog.html', [])


def registry(request, name):
    """get tag list
    """
    url = "https://192.168.3.110:5000/v2/" + name + "/tags/list"
    response = req(url)
    if response is not None:
        context = {"catalog": response["tags"]}
        return render(request, 'catalog.html', context)
    return render(request, 'catalog.html', [])
