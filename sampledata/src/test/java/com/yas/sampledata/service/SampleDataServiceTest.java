package com.yas.sampledata.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.yas.sampledata.utils.SqlScriptExecutor;
import com.yas.sampledata.viewmodel.SampleDataVm;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.mockito.MockedConstruction;
import org.mockito.Mockito;

class SampleDataServiceTest {

    @Test
    void createSampleData_shouldExecuteProductAndMediaScripts() {
        DataSource productDataSource = mock(DataSource.class);
        DataSource mediaDataSource = mock(DataSource.class);

        try (MockedConstruction<SqlScriptExecutor> mocked = Mockito.mockConstruction(SqlScriptExecutor.class)) {
            SampleDataService sampleDataService = new SampleDataService(productDataSource, mediaDataSource);

            SampleDataVm result = sampleDataService.createSampleData();

            assertThat(result.message()).isEqualTo("Insert Sample Data successfully!");
            assertThat(mocked.constructed()).hasSize(1);
            SqlScriptExecutor executor = mocked.constructed().get(0);
            verify(executor).executeScriptsForSchema(productDataSource, "public", "classpath*:db/product/*.sql");
            verify(executor).executeScriptsForSchema(mediaDataSource, "public", "classpath*:db/media/*.sql");
        }
    }
}
