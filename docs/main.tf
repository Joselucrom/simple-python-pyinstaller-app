terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins" {
  name = "jenkins-network"
}

resource "docker_volume" "docker_certs" {
  name = "jenkins-docker-certs"
}



resource "docker_container" "dind" {
  name  = "jenkins-docker"
  image = "docker:dind"
  privileged = true

  env = [
    "DOCKER_TLS_CERTDIR=/certs",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_HOST=tcp://0.0.0.0:2376",
    "DOCKER_TLS_VERIFY=1"
  ]

  networks_advanced {
    name = docker_network.jenkins.name
    aliases = ["docker"]
  }

  volumes {
    volume_name    = "jenkins-docker-certs"
    container_path = "/certs"
  }

  ports {
    internal = 2376
    external = 2376
  }
}


resource "docker_container" "jenkins" {
  name  = "jenkins-blueocean"
  image = "myjenkins-blueocean"
  restart = "on-failure"

  env = [
    "DOCKER_HOST=tcp://jenkins-docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]

  networks_advanced {
    name = docker_network.jenkins.name
  }

  ports {
    internal = 8080
    external = 8080
  }

  volumes {
    volume_name    = "jenkins-docker-certs"
    container_path = "/certs/client"
  }

  depends_on = [docker_container.dind]
}


