package com.yas.sampledata.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

class SqlScriptExecutorTest {

    @Test
    void executeScriptsForSchema_shouldRunMatchingScriptsInOrder() {
        DataSource dataSource = h2DataSource();
        SqlScriptExecutor executor = new SqlScriptExecutor();

        executor.executeScriptsForSchema(dataSource, "PUBLIC", "classpath*:db/test/*.sql");

        Integer count = new JdbcTemplate(dataSource).queryForObject("select count(*) from sample_item", Integer.class);
        assertThat(count).isEqualTo(2);
    }

    @Test
    void executeScriptsForSchema_shouldWrapScriptFailures() {
        DataSource dataSource = h2DataSource();
        SqlScriptExecutor executor = new SqlScriptExecutor();

        assertThatThrownBy(() ->
            executor.executeScriptsForSchema(dataSource, "PUBLIC", "classpath*:db/invalid/*.sql"))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("Failed to execute sample data scripts from classpath*:db/invalid/*.sql");
    }

    private DataSource h2DataSource() {
        DriverManagerDataSource dataSource = new DriverManagerDataSource();
        dataSource.setDriverClassName("org.h2.Driver");
        dataSource.setUrl("jdbc:h2:mem:" + System.nanoTime() + ";MODE=PostgreSQL;DB_CLOSE_DELAY=-1");
        dataSource.setUsername("sa");
        dataSource.setPassword("");
        return dataSource;
    }
}
