package io.github.mmhelloworld.idris2.runtime;

import java.math.BigInteger;

public interface IdrisClock {
    BigInteger getSeconds();
    BigInteger getNanoSeconds();
}
