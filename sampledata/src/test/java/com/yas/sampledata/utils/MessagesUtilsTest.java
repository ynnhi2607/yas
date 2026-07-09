package com.yas.sampledata.utils;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class MessagesUtilsTest {

    @Test
    void getMessage_shouldReturnCodeWhenMessageIsMissing() {
        assertThat(MessagesUtils.getMessage("missing.message.code")).isEqualTo("missing.message.code");
    }
}
