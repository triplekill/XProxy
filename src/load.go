package main

import (
    log "github.com/sirupsen/logrus"
    "io"
    "io/ioutil"
    "os"
    "strings"
)

var logConfig = `{
  "log": {
    "loglevel": "${LEVEL}",
    "access": "${DIR}/access.log",
    "error": "${DIR}/error.log"
  }
}`

var dnsConfig = `{
  "dns": {
    "servers": [
      "localhost"
    ]
  }
}`

var routeConfig = `{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "node"
      }
    ]
  }
}`

var outboundsConfig = `{
  "outbounds": [
    {
      "tag": "node",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}`

func isFileExist(filePath string) bool {
    s, err := os.Stat(filePath)
    if err != nil { // file or folder not exist
        return false
    }
    return !s.IsDir()
}

func createFolder(folderPath string) {
    log.Debugf("Loading folder -> %s", folderPath)
    err := os.MkdirAll(folderPath, 0755)
    if err != nil {
        log.Errorf("Failed to create folder -> %s", folderPath)
        panic("Create folder failed")
    }
}

func listFolder(folderPath string, suffix string) []string {
    var fileList []string
    files, err := ioutil.ReadDir(folderPath)
    if err != nil {
        log.Errorf("Failed to list folder -> %s", folderPath)
        panic("List folder failed")
    }
    for _, file := range files {
        if strings.HasSuffix(file.Name(), suffix) {
            fileList = append(fileList, file.Name())
        }
    }
    return fileList
}

func copyFile(source string, target string) {
    log.Infof("Copy file `%s` => `%s`", source, target)
    srcFile, err := os.Open(source)
    if err != nil {
        log.Errorf("Failed to open file -> %s", source)
        panic("Open file failed")
    }
    dstFile, err := os.OpenFile(target, os.O_WRONLY|os.O_TRUNC|os.O_CREATE, 0644)
    if err != nil {
        log.Errorf("Failed to open file -> %s", target)
        panic("Open file failed")
    }
    _, err = io.Copy(dstFile, srcFile)
    if err != nil {
        log.Errorf("Failed to copy from `%s` to `%s`", source, target)
        panic("Copy file failed")
    }
}

func saveConfig(configDir string, caption string, content string, overwrite bool) {
    filePath := configDir + "/" + caption + ".json"
    if !overwrite && isFileExist(filePath) { // file exist and don't overwrite
        log.Debugf("Skip loading config -> %s", filePath)
        return
    }
    log.Debugf("Loading %s -> \n%s", filePath, content)
    err := os.WriteFile(filePath, []byte(content), 0644)
    if err != nil {
        log.Errorf("File %s -> %v", caption, err)
        panic("File save error")
    }
}

func loadProxy(configDir string, exposeDir string) {
    createFolder(exposeDir + "/log")
    createFolder(exposeDir + "/config")
    createFolder(configDir)
    saveConfig(exposeDir+"/config", "dns", dnsConfig+"\n", false)
    saveConfig(exposeDir+"/config", "route", routeConfig+"\n", false)
    saveConfig(exposeDir+"/config", "outbounds", outboundsConfig+"\n", false)

    logConfig = strings.ReplaceAll(logConfig, "${LEVEL}", logLevel)
    logConfig = strings.ReplaceAll(logConfig, "${DIR}", exposeDir+"/log")
    saveConfig(configDir, "log", logConfig+"\n", true)

    // TODO: load inbounds config

    for _, configFile := range listFolder(exposeDir+"/config", ".json") {
        if configFile == "log.json" || configFile == "inbounds.json" {
            log.Warningf("Config file `%s` will be overrided", configFile)
        }
        copyFile(exposeDir+"/config/"+configFile, configDir+"/"+configFile)
    }
}