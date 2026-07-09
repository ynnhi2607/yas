package com.yas.sampledata.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.yas.sampledata.service.SampleDataService;
import com.yas.sampledata.viewmodel.SampleDataVm;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

class SampleDataControllerTest {

    @Test
    void createSampleData_shouldReturnServiceResult() {
        SampleDataService sampleDataService = Mockito.mock(SampleDataService.class);
        SampleDataVm expected = new SampleDataVm("ok");
        when(sampleDataService.createSampleData()).thenReturn(expected);

        SampleDataController controller = new SampleDataController(sampleDataService);

        SampleDataVm actual = controller.createSampleData();

        assertThat(actual).isEqualTo(expected);
        verify(sampleDataService).createSampleData();
    }
}
