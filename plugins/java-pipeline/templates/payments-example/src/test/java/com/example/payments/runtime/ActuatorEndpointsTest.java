package com.example.payments.runtime;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/** Kubernetes probes are served; nothing else from Actuator is reachable, and health shows no internals. */
@SpringBootTest
@AutoConfigureMockMvc
class ActuatorEndpointsTest {

    @Autowired
    MockMvc mvc;

    @ParameterizedTest
    @ValueSource(strings = {"/actuator/health/liveness", "/actuator/health/readiness"})
    void kubernetes_probes_report_up(String probe) throws Exception {
        mvc.perform(get(probe))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void health_shows_status_only_without_components_or_details() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(content().string(not(containsString("components"))))
                .andExpect(content().string(not(containsString("details"))));
    }

    @ParameterizedTest
    @ValueSource(strings = {"/actuator/env", "/actuator/beans", "/actuator/metrics", "/actuator/configprops"})
    void other_actuator_endpoints_are_not_exposed(String endpoint) throws Exception {
        // Exactly 404. /java-pipeline:add-resource-server splits this into "with a token → 404" and
        // "without → 401" when it puts the API behind tokens.
        mvc.perform(get(endpoint))
                .andExpect(status().isNotFound())
                .andExpect(content().string(not(containsString("propertySources"))));
    }
}
