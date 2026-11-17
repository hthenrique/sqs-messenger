package com.sqsmessenger.config;

import java.util.Properties;
import java.util.function.Function;

/**
 * SMTP configuration loaded from environment variables.
 */
public record SmtpConfig(
        String host,
        int port,
        String username,
        String password,
        String from,
        boolean auth,
        boolean starttls,
        boolean ssl,
        int connectionTimeoutMs,
        int timeoutMs
) {
    private static final int DEFAULT_PORT = 587;
    private static final int DEFAULT_TIMEOUT_MS = 10_000;

    public static SmtpConfig fromEnv() {
        return fromEnv(System::getenv);
    }

    public static SmtpConfig fromEnv(Function<String, String> env) {
        String host = requireNonBlank(env.apply("SMTP_HOST"), "SMTP_HOST");
        int port = parseIntOrDefault(env.apply("SMTP_PORT"), DEFAULT_PORT);
        boolean auth = parseBooleanOrDefault(env.apply("SMTP_AUTH"), true);
        boolean starttls = parseBooleanOrDefault(env.apply("SMTP_STARTTLS"), true);
        boolean ssl = parseBooleanOrDefault(env.apply("SMTP_SSL"), false);

        String username = trimToNull(env.apply("SMTP_USERNAME"));
        String password = env.apply("SMTP_PASSWORD");
        if (auth) {
            if (username == null) {
                throw new IllegalStateException("Environment variable 'SMTP_USERNAME' is required when SMTP_AUTH=true.");
            }
            if (password == null || password.isBlank()) {
                throw new IllegalStateException("Environment variable 'SMTP_PASSWORD' is required when SMTP_AUTH=true.");
            }
        }

        String from = trimToNull(env.apply("SMTP_FROM"));
        if (from == null) {
            from = username;
        }
        if (from == null) {
            throw new IllegalStateException("Environment variable 'SMTP_FROM' (or 'SMTP_USERNAME') must be set.");
        }

        int connectionTimeoutMs = parseIntOrDefault(env.apply("SMTP_CONNECTION_TIMEOUT_MS"), DEFAULT_TIMEOUT_MS);
        int timeoutMs = parseIntOrDefault(env.apply("SMTP_TIMEOUT_MS"), DEFAULT_TIMEOUT_MS);

        return new SmtpConfig(host, port, username, password, from, auth, starttls, ssl, connectionTimeoutMs, timeoutMs);
    }

    public Properties toMailProperties() {
        Properties props = new Properties();
        props.put("mail.smtp.host", host);
        props.put("mail.smtp.port", String.valueOf(port));
        props.put("mail.smtp.auth", String.valueOf(auth));
        props.put("mail.smtp.starttls.enable", String.valueOf(starttls));
        props.put("mail.smtp.ssl.enable", String.valueOf(ssl));
        props.put("mail.smtp.connectiontimeout", String.valueOf(connectionTimeoutMs));
        props.put("mail.smtp.timeout", String.valueOf(timeoutMs));
        props.put("mail.smtp.writetimeout", String.valueOf(timeoutMs));
        return props;
    }

    private static String requireNonBlank(String value, String name) {
        String trimmed = trimToNull(value);
        if (trimmed == null) {
            throw new IllegalStateException("Required environment variable '" + name + "' is not set.");
        }
        return trimmed;
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static int parseIntOrDefault(String value, int defaultValue) {
        String trimmed = trimToNull(value);
        if (trimmed == null) {
            return defaultValue;
        }
        return Integer.parseInt(trimmed);
    }

    private static boolean parseBooleanOrDefault(String value, boolean defaultValue) {
        String trimmed = trimToNull(value);
        if (trimmed == null) {
            return defaultValue;
        }
        return Boolean.parseBoolean(trimmed);
    }
}
