//
//  FindLicenseJavaScript.swift
//  
//
//  Created by Helge Heß on 30.05.20.
//

internal let FindLicenseJavaScript =
"""
document.addEventListener("readystatechange", function() {
  function zzFindLicenses() {
    return document.getElementById("viewdata").innerHTML;
  }
  if (document.readyState == "complete") {
    const licenses = zzFindLicenses();
    console.log("found licenses:", licenses);
    window.webkit.messageHandlers.zz.postMessage(licenses);
  }
});
"""
