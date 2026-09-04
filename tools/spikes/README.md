# spikes

一次性的技术验证程序，目的是尽早证伪，不追求代码质量。

- `android_gps/` —— **S0，项目的生死线**。
  验证 OPPO (ColorOS) 上能否真正读到照片的 GPS。
  Android 10+ 默认抹掉 MediaStore 里的位置，必须申请 `ACCESS_MEDIA_LOCATION`
  并对 URI 调 `setRequireOriginal()`。`photo_manager` 这块大概率要补原生代码。
  这个验证不通过，整个项目不成立。
