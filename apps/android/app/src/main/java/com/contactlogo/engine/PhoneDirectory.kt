package com.contactlogo.engine

object PhoneDirectory {
    private val directory = mapOf(
        "8002211212" to "delta.com",
        "8008648331" to "united.com",
        "8004337300" to "aa.com",
        "8004359792" to "southwest.com",
        "8004633339" to "fedex.com",
        "8007425877" to "ups.com",
        "8002758777" to "usps.com",
        "8009254733" to "walgreens.com",
        "8007467287" to "cvs.com",
        "8009256278" to "walmart.com",
        "8004400680" to "target.com",
        "8004663337" to "homedepot.com"
    )

    fun digitsOnly(phone: String): String {
        return phone.replace(Regex("""[^0-9]"""), "")
    }

    fun domainForPhone(phone: String): String? {
        val d = digitsOnly(phone)
        val last10 = if (d.length >= 10) d.takeLast(10) else d
        return directory[last10]
    }

    fun isBusinessPhone(phone: String): Boolean {
        val d = digitsOnly(phone)
        val last10 = if (d.length >= 10) d.takeLast(10) else d
        if (directory.containsKey(last10)) return true
        return last10.startsWith("800") || last10.startsWith("888") ||
               last10.startsWith("877") || last10.startsWith("866") ||
               last10.startsWith("855") || last10.startsWith("844") ||
               last10.startsWith("833")
    }
}
