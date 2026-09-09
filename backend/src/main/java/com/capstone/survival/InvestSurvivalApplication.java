package com.capstone.survival;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@SpringBootApplication
public class InvestSurvivalApplication {

	@Bean
	public RestTemplate restTemplate() {
		SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
		factory.setConnectTimeout(3000);   // 연결 3초
		factory.setReadTimeout(30000);     // 응답 30초 (LLM 생성 시간 고려)
		return new RestTemplate(factory);
	}

	public static void main(String[] args) {
		SpringApplication.run(InvestSurvivalApplication.class, args);
	}

}
