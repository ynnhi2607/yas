package com.yas.sampledata.utils;

import java.io.IOException;
import java.sql.Connection;
import java.util.Arrays;
import java.util.Comparator;
import javax.sql.DataSource;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.stereotype.Component;

@Component
@Slf4j
public class SqlScriptExecutor {

    public void executeScriptsForSchema(DataSource dataSource, String schema, String locationPattern) {
        PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
        try {
            Resource[] resources = resolver.getResources(locationPattern);
            Arrays.sort(resources, Comparator.comparing(this::resourceName));

            for (Resource resource : resources) {
                executeSqlScript(dataSource, schema, resource);
            }
        } catch (Exception e) {
            throw new IllegalStateException("Failed to execute sample data scripts from " + locationPattern, e);
        }
    }

    private void executeSqlScript(DataSource dataSource, String schema, Resource resource) {
        try (Connection connection = dataSource.getConnection()) {
            connection.setSchema(schema); // Set the schema
            ScriptUtils.executeSqlScript(connection, resource);
            log.info("Executed script: {} on schema: {}", resourceName(resource), schema);
        } catch (Exception e) {
            throw new IllegalStateException(
                "Failed to execute script " + resourceName(resource) + " on schema " + schema, e);
        }
    }

    private String resourceName(Resource resource) {
        try {
            return resource.getURL().toString();
        } catch (IOException e) {
            return resource.getFilename();
        }
    }
}
