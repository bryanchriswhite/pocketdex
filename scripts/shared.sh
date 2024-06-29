#!/bin/sh

warning_log() {
  echo -e "\033[1;33mWARN:\033[0m $1"
}

error_log() {
  echo -e "\033[1;31mERROR:\033[0m $1"
}

info_log() {
  echo -e "\033[1;32mINFO:\033[0m $1"
}
