#!/bin/bash
# creates data directories for postgres, pgadmin, jenkins, nexus and gitea

# postgres
sudo mkdir -p /opt/devops/postgres/data
sudo mkdir -p /opt/devops/postgres/initdb

# pgadmin
sudo mkdir -p /opt/devops/pgadmin/data
sudo chown -R 5050:5050 /opt/devops/pgadmin/data

# jenkins
sudo mkdir -p /opt/devops/jenkins/home

# nexus
sudo mkdir -p /opt/devops/nexus/home
sudo chown -R 200:200 /opt/devops/nexus/home

# gitea
sudo mkdir -p /opt/devops/gitea/data


# nuke all 
# sudo rm -rf /opt/devops/postgres/data
# sudo rm -rf /opt/devops/postgres/initdb
# sudo rm -rf /opt/devops/pgadmin/data
# sudo rm -rf /opt/devops/jenkins/home
# sudo rm -rf /opt/devops/nexus/home
# sudo rm -rf /opt/devops/gitea/data