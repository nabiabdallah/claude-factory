package __PKG__.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Rollout rule for migrations (claude-factory ADR 0012). During a rolling update the previous version runs
 * against the new schema. A migration with a statement the previous version may not survive must say, on its
 * first line, how it rolls out:
 *
 * <pre>
 * -- rollout: compatible — &lt;why the running version is unaffected, e.g. column unused since V5&gt;
 * -- rollout: recreate — &lt;why it breaks; the release then stops all old pods first (downtime)&gt;
 * </pre>
 *
 * Prefer expand/contract (add, migrate, stop using, then drop in a later release) so it stays "compatible".
 * {@code .github/scripts/check-deploy.sh} turns "recreate" into a required {@code components/recreate} on the
 * promotion that crosses it.
 */
class MigrationRolloutTest {

    static final Path MIGRATIONS = Path.of("src/main/resources/db/migration");

    static final Pattern HEADER = Pattern.compile("^-- rollout: (recreate|compatible) [—-]+ \\S.{9,}$");

    /** Statements the previous version may not survive: it still reads, writes or relies on the old shape. */
    static final List<Pattern> RISKY = Stream.of(
                    "\\bdrop\\s+(table|column|view|materialized\\s+view|schema|type|function|sequence)\\b",
                    "^alter\\s+table\\b.*\\bdrop\\s+(?!constraint\\b|default\\b|not\\s+null\\b)\\w+",
                    "\\brename\\b",
                    "\\balter\\s+column\\s+\\S+\\s+(set\\s+data\\s+)?type\\b",
                    "\\bset\\s+not\\s+null\\b",
                    "^alter\\s+table\\b.*\\badd\\s+(constraint|check|unique|primary\\s+key|foreign\\s+key|exclude)\\b",
                    "^alter\\s+table\\b(?!.*\\bdefault\\b).*\\badd\\b(?!\\s+(constraint|check|unique|primary|foreign|exclude)\\b).*\\bnot\\s+null\\b",
                    "^create\\s+unique\\s+index\\b")
            .map(Pattern::compile)
            .toList();

    @Test
    void every_risky_migration_declares_how_it_rolls_out() throws IOException {
        List<String> problems = new ArrayList<>();
        try (Stream<Path> files = Files.list(MIGRATIONS)) {
            for (Path file : files.filter(f -> f.toString().endsWith(".sql")).sorted().toList()) {
                problems.addAll(check(file.getFileName().toString(), Files.readString(file)));
            }
        }
        assertThat(problems)
                .as("Start each of these migrations with '-- rollout: compatible — <why>' or"
                        + " '-- rollout: recreate — <why>' (see this test's Javadoc)")
                .isEmpty();
    }

    @ParameterizedTest
    @ValueSource(
            strings = {
                "alter table account drop column legacy_id;",
                "ALTER TABLE account DROP legacy_id;",
                "drop table audit;",
                "alter table account rename column owner to owner_subject;",
                "alter table account rename to accounts;",
                "alter table account alter column balance type numeric(19, 4);",
                "alter table account alter column owner set not null;",
                "alter table account add column owner text not null;",
                "alter table account add constraint owner_len check (length(owner) <= 255);",
                "alter table account add unique (owner);",
                "alter table transfer add foreign key (account_id) references account (id);",
                "create unique index account_owner on account (owner);",
                "/* safe? */ alter table account\n  drop column x;"
            })
    void flags_statements_the_previous_version_may_not_survive(String sql) {
        assertThat(check("V9__x.sql", sql)).hasSize(1);
        assertThat(check("V9__x.sql", "-- rollout: compatible — column unused since V5\n" + sql))
                .isEmpty();
        assertThat(check("V9__x.sql", "-- rollout: recreate — old version reads the column\n" + sql))
                .isEmpty();
    }

    @ParameterizedTest
    @ValueSource(
            strings = {
                "select 1;",
                "create table customer (id uuid primary key, name text not null unique);",
                "alter table account add column nickname text;",
                "alter table account add column status text not null default 'ACTIVE';",
                "alter table account alter column owner drop not null;",
                "alter table account drop constraint owner_len;",
                "create index account_owner on account (owner);",
                "insert into account (id) values ('x');",
                "-- drop table account;\nselect 1;"
            })
    void lets_expand_only_changes_through(String sql) {
        assertThat(check("V9__x.sql", sql)).isEmpty();
    }

    @ParameterizedTest
    @ValueSource(
            strings = {
                "-- rollout: maybe — not a known mode\ndrop table audit;",
                "-- rollout: recreate\ndrop table audit;",
                "select 1;\n-- rollout: recreate — header is not on the first line\ndrop table audit;"
            })
    void rejects_malformed_or_misplaced_headers(String sql) {
        assertThat(check("V9__x.sql", sql)).isNotEmpty();
    }

    static List<String> check(String name, String sql) {
        String firstLine = sql.lines().findFirst().orElse("").strip();
        boolean declared = HEADER.matcher(firstLine).matches();
        List<String> problems = new ArrayList<>();
        if (!declared && firstLine.startsWith("-- rollout:")) {
            problems.add(name + ": malformed rollout header: " + firstLine);
        }
        if (!declared && sql.lines().skip(1).anyMatch(l -> l.strip().startsWith("-- rollout:"))) {
            problems.add(name + ": the rollout header must be the first line");
        }
        if (!declared) {
            firstRisky(sql).ifPresent(s -> problems.add(name + ": undeclared rollout risk: " + s));
        }
        return problems;
    }

    static Optional<String> firstRisky(String sql) {
        String code = sql.replaceAll("(?s)/\\*.*?\\*/", " ").replaceAll("--[^\\n]*", " ");
        for (String statement : code.split(";")) {
            String s = statement.strip().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
            if (!s.isEmpty() && RISKY.stream().anyMatch(p -> p.matcher(s).find())) {
                return Optional.of(s.length() > 120 ? s.substring(0, 120) + "…" : s);
            }
        }
        return Optional.empty();
    }
}
