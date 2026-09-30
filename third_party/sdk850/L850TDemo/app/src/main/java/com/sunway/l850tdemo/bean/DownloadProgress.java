package com.sunway.l850tdemo.bean;

import java.io.File;

/** desc：
 * create at 2026/3/30 9:35 by liuxiong
 */
public class DownloadProgress {

    public enum Status { PROGRESS, COMPLETED, ERROR }

    private final Status status;

    private int progress = 0;
    private String  message = "";

    private File downLoadFile;


    public DownloadProgress(Status status, int progress) {
        this.status = status;
        this.progress = progress;
    }

    public DownloadProgress(Status status, String message) {
        this.status = status;
        this.message = message;
    }
    public DownloadProgress(Status status, File downLoadFile) {
        this.status = status;
        this.downLoadFile = downLoadFile;
    }



    public static DownloadProgress progress(int progress){
        return new DownloadProgress(Status.PROGRESS,progress);
    }

    public static DownloadProgress complete(File downLoadFile){
        return new DownloadProgress(Status.COMPLETED,downLoadFile);
    }

    public static DownloadProgress error(String message){
        return new DownloadProgress(Status.ERROR,message);
    }

    public void setProgress(int progress) {
        this.progress = progress;
    }

    public int getProgress() {
        return progress;
    }

    public String getMessage() {
        return message;
    }

    public Status getStatus() {
        return status;
    }

    public File getDownLoadFile() {
        return downLoadFile;
    }

    public void setDownLoadFile(File downLoadFile) {
        this.downLoadFile = downLoadFile;
    }
}
