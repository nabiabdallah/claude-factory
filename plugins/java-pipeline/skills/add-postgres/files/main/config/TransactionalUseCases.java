package __PKG__.config;

import org.springframework.aop.framework.ProxyFactory;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.interceptor.DefaultTransactionAttribute;
import org.springframework.transaction.interceptor.TransactionInterceptor;

/**
 * Runs every call of a use case in one database transaction, without putting Spring into
 * {@code application/}. Wrap the use-case bean where it is wired:
 *
 * <pre>{@code
 * @Bean
 * OpenAccountUseCase openAccountUseCase(AccountRepository accounts, PlatformTransactionManager tx) {
 *     return TransactionalUseCases.wrap(OpenAccountUseCase.class, new OpenAccountService(accounts), tx);
 * }
 * }</pre>
 *
 * <p>Semantics are Spring's defaults: join an existing transaction or start one; commit when the call
 * returns; roll back on any {@link RuntimeException} or {@link Error}, including domain exceptions.
 */
public final class TransactionalUseCases {

    private TransactionalUseCases() {}

    public static <T> T wrap(Class<T> port, T useCase, PlatformTransactionManager transactionManager) {
        if (!port.isInterface()) {
            throw new IllegalArgumentException(port.getName() + " must be an interface (an inbound port)");
        }
        var factory = new ProxyFactory(useCase);
        factory.setInterfaces(port);
        factory.addAdvice(new TransactionInterceptor(
                transactionManager,
                (method, targetClass) ->
                        method.getDeclaringClass() == Object.class ? null : new DefaultTransactionAttribute()));
        return port.cast(factory.getProxy());
    }
}
