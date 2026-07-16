variable "REGISTRY" {
  default = ""
}

variable "TAG" {
  default = "dev"
}

variable "BASE_IMAGE" {
  default = "alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest"
}

variable "NODE_MAJOR" {
  default = "20"
}

variable "NVIM_VERSION" {
  default = "0.11.3"
}

variable "STARSHIP_VERSION" {
  default = "1.25.1"
}

variable "ZOXIDE_VERSION" {
  default = "0.9.9"
}

variable "FZF_VERSION" {
  default = "0.72.0"
}

group "default" {
  targets = ["alinux3-full"]
}

target "common" {
  context    = "."
  dockerfile = "containers/alinux3/Dockerfile"
  args = {
    BASE_IMAGE      = BASE_IMAGE
    NODE_MAJOR      = NODE_MAJOR
    NVIM_VERSION    = NVIM_VERSION
    STARSHIP_VERSION = STARSHIP_VERSION
    ZOXIDE_VERSION  = ZOXIDE_VERSION
    FZF_VERSION     = FZF_VERSION
  }
}

target "alinux3-minimal" {
  inherits = ["common"]
  tags = ["${REGISTRY}devtools-alinux3:minimal-${TAG}"]
  target = "minimal"
}

target "alinux3-full" {
  inherits = ["common"]
  tags = ["${REGISTRY}devtools-alinux3:full-${TAG}"]
  target = "full"
}

target "alinux3-ssh" {
  inherits = ["common"]
  tags = ["${REGISTRY}devtools-alinux3:ssh-${TAG}"]
  target = "ssh"
}
