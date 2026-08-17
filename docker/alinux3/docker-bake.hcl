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

variable "LAZYGIT_VERSION" {
  default = "0.44.1"
}

variable "BAT_VERSION" {
  default = "0.25.0"
}

variable "RG_VERSION" {
  default = "14.1.1"
}

variable "YAZI_VERSION" {
  default = "0.3.3"
}

variable "HTTP_PROXY" {
  default = ""
}

variable "HTTPS_PROXY" {
  default = ""
}

variable "NO_PROXY" {
  default = "localhost,127.0.0.1,::1,mirrors.aliyun.com,.aliyun.com,.aliyuncs.com"
}

group "default" {
  targets = ["devbox"]
}

target "devbox" {
  context    = "../.."
  dockerfile = "docker/alinux3/Dockerfile"
  platforms  = ["linux/amd64"]
  args = {
    BASE_IMAGE       = BASE_IMAGE
    NODE_MAJOR       = NODE_MAJOR
    LAZYGIT_VERSION  = LAZYGIT_VERSION
    BAT_VERSION      = BAT_VERSION
    RG_VERSION       = RG_VERSION
    YAZI_VERSION     = YAZI_VERSION
    HTTP_PROXY       = HTTP_PROXY
    HTTPS_PROXY      = HTTPS_PROXY
    NO_PROXY         = NO_PROXY
    http_proxy       = HTTP_PROXY
    https_proxy      = HTTPS_PROXY
    no_proxy         = NO_PROXY
  }
  tags = [
    "${REGISTRY}alinux3-devbox:${TAG}",
    "${REGISTRY}alinux3-devbox:latest",
  ]
}
