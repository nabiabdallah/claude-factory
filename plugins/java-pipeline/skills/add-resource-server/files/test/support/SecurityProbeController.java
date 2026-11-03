package __PKG__.support;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** Test-only endpoints for SecurityTest, so the security rules are tested even before the service has APIs. */
@RestController
class SecurityProbeController {

    @GetMapping("/security-probe")
    String read() {
        return "read-ok";
    }

    @PostMapping("/security-probe")
    String write() {
        return "write-ok";
    }
}
