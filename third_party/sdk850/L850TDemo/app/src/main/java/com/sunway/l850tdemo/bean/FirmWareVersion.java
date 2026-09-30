package com.sunway.l850tdemo.bean;

/**
     * {
     *      "firmwareId":56,
     *      "name":"9170076-L808E-SWP31-拉力器配上田2个小功率电机控制器程序",
     *      "productModel":"L808E",
     *      "code":"9170076",
     *      "path":"9170076",
     *      "version":15,
     *      "url":"https://tft.sunwayelectronic.com/bin/9170076/56_15_1758348045310.bin",
     *      "created_at":"2025-09-19T22:00:46.000Z"
     * }
     * */
    public  class FirmWareVersion {
        private Long firmwareId;
        private String name;
        private String productModel;
        private String code;
        private String path;
        private Long version;
        private String url;

        // 对应 @SerialName("created_at")
        private String created_at;

        public FirmWareVersion() {}

        public Long getFirmwareId() {
            return firmwareId;
        }

        public void setFirmwareId(Long firmwareId) {
            this.firmwareId = firmwareId;
        }

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }

        public String getProductModel() {
            return productModel;
        }

        public void setProductModel(String productModel) {
            this.productModel = productModel;
        }

        public String getCode() {
            return code;
        }

        public void setCode(String code) {
            this.code = code;
        }

        public String getPath() {
            return path;
        }

        public void setPath(String path) {
            this.path = path;
        }

        public Long getVersion() {
            return version;
        }

        public void setVersion(Long version) {
            this.version = version;
        }

        public String getUrl() {
            return url;
        }

        public void setUrl(String url) {
            this.url = url;
        }

        public String getCreated_at() {
            return created_at;
        }

        public void setCreated_at(String created_at) {
            this.created_at = created_at;
        }

        @Override
        public String toString() {
            return "FirmWareVersion{" +
                    "firmwareId=" + firmwareId +
                    ", name='" + name + '\'' +
                    ", productModel='" + productModel + '\'' +
                    ", code='" + code + '\'' +
                    ", path='" + path + '\'' +
                    ", version=" + version +
                    ", url='" + url + '\'' +
                    ", created_at='" + created_at + '\'' +
                    '}';
        }
    }