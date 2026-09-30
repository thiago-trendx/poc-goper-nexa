# Regras de R8/ProGuard aplicadas a qualquer app que use o plugin sdk850_bridge (plano, seção 5.5).

# O código nativo da serial (libserial_port.so) busca campos e métodos de
# android.serialport.SerialPort pelo nome (por exemplo o campo mFd). Se o R8 renomear esses
# membros, SerialPort.close() derruba o processo com:
#   NoSuchFieldError: no "Ljava/io/FileDescriptor;" field "mFd" in class "Landroid/serialport/SerialPort;"
# (observado em build release no tablet de bancada ao tocar em "Desconectar").
-keep class android.serialport.** { *; }

# O SDK 850 já vem ofuscado pelo fabricante e usa reflexão/JNI internamente; não ofuscar de novo.
-keep class com.sunway.sdk850.** { *; }
