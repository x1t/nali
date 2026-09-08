package migration

import (
	"log"
	"strings"

	"github.com/spf13/viper"
	"github.com/zu1k/nali/internal/constant"
	"github.com/zu1k/nali/internal/db"
	"github.com/zu1k/nali/pkg/ip2region"
)

func migration2v8() {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(constant.ConfigDirPath)

	if err := viper.ReadInConfig(); err != nil {
		return
	}

	dbList := db.List{}
	if err := viper.UnmarshalKey("databases", &dbList); err != nil {
		log.Fatalln("Config invalid:", err)
	}

	needOverwrite := false
	for _, database := range dbList {
		if database.Name == "ip2region" && len(database.DownloadUrls) > 0 &&
			strings.Contains(database.DownloadUrls[0], "ip2region.xdb") {
			database.DownloadUrls = ip2region.DownloadUrls
			needOverwrite = true
		}
	}

	if needOverwrite {
		viper.Set("databases", dbList)
		if err := viper.WriteConfig(); err != nil {
			log.Println(err)
		}
	}
}
