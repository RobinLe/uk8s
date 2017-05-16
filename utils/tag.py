#!/usr/bin/python
from subprocess import call
import json

with open("/var/lib/docker/image/aufs/repositories.json", "r") as f:
    REPO = json.loads(f.read())

for repo in REPO["Repositories"]:
    if repo[:6] == "gcr.io":
        for image in REPO["Repositories"][repo]:
            if "@" in image:
                continue
            newtag = "uk8s.com" + image[6:]
            print newtag
            call(["docker", "tag", image, newtag])
            call(["docker", "push", newtag])
            