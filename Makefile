VERSION ?= latest

.PHONY: all build image start clean logs

all: clean prepare build start

build: 
	docker build -t opennebula:$(VERSION) .

start: 
	docker run --rm --name one -d --privileged -p 80:9869 opennebula 

clean:
	-docker rm -f one

logs:
	docker logs one


prepare: id_rsa

id_rsa:
	ssh-keygen -t rsa -b 4096 -P "" -f ./id_rsa