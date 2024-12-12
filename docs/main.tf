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

resource "docker_container" "dind" {
  name  = "jenkins-docker"
  image = "docker:dind"
  privileged = true

  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

  networks_advanced {
    name = docker_network.jenkins.name
    aliases = ["docker"]
  }

  volumes {
    volume_name    = "jenkins-docker-certs"
    container_path = "/certs/client"
  }
}

resource "docker_container" "jenkins" {
  name  = "jenkins-blueocean"
  image = "myjenkins-blueocean"
  restart = "on-failure"

  env = [
    "DOCKER_HOST=tcp://docker:2376",
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
    volume_name    = "jenkins-data"
    container_path = "/var/jenkins_home"
  }
}
