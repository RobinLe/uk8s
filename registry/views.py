# -*- coding: utf-8 -*-
from __future__ import unicode_literals
from django.shortcuts import render

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

def catalog(request):
    """get registry catalog
    """
    response = requests.get("https://192.168.3.110:5000/v2/_catalog", verify=False)
    if response.status_code == 200:
        context = {'catalog': response.text}
        return render(request, 'catalog.html', context)

