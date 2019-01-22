#! /bin/bash

sudo apt-get purge -y maven

cd /usr/local/src/

wget http://apache.is.co.za/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz

tar -zxf apache-maven-3.3.9-bin.tar.gz

sudo cp -R apache-maven-3.3.9 /usr/local/src
sudo ln -s /usr/local/src/apache-maven-3.3.9/bin/mvn /usr/bin/mvn

echo "export M2_HOME=/usr/local/apache-maven-3.3.9" >> ~/.profile

source ~/.profile

echo "Maven is on version `mvn -v`"
