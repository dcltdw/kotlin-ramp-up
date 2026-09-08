package dev.dcltdw.catalog.api

import org.springframework.beans.factory.annotation.Value
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

/**
 * The Day 1 endpoint. It exists to prove the deployment pipeline works end to
 * end — build, image, EC2, security group, reachable over HTTP — and nothing
 * more. The catalog and rules endpoints are hand-written on Days 2 and 3.
 */
@RestController
@RequestMapping("/api")
class PingController(
    @param:Value("\${spring.application.name}") private val service: String,
    @param:Value("\${info.app.version}") private val version: String,
) {
    @GetMapping("/ping")
    fun ping(): PingResponse = PingResponse(service = service, version = version)
}

data class PingResponse(
    val service: String,
    val version: String,
    val status: String = "ok",
)
