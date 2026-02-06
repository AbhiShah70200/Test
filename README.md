import feign.QueryMap;
import feign.RequestLine;
import java.util.Map;

public interface ProcessApiClient {

    @RequestLine("GET /process")
    Map<String, Object> getProcess(@QueryMap Map<String, Object> queryParams);
}


import com.fasterxml.jackson.databind.ObjectMapper;
import feign.Feign;
import feign.Request;
import feign.jackson.JacksonDecoder;
import feign.jackson.JacksonEncoder;

import java.util.concurrent.TimeUnit;

public class FeignConfig {

    public static ProcessApiClient createClient(String baseUrl) {

        ObjectMapper mapper = new ObjectMapper();

        return Feign.builder()
                .encoder(new JacksonEncoder(mapper))
                .decoder(new JacksonDecoder(mapper))
                .options(new Request.Options(
                        10, TimeUnit.SECONDS,
                        20, TimeUnit.SECONDS,
                        true
                ))
                .target(ProcessApiClient.class, baseUrl);
    }

    import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class DynamicApiBatchRunner {

    static final String BASE_URL = "https://api.example.com"; // change
    static final int MAX_RETRIES = 3;
    static final int REQUESTS_PER_SECOND = 20;

    public static void main(String[] args) throws Exception {

        // Example: each map can have 1 param or many
        List<Map<String, Object>> requests = List.of(
                Map.of("process_id", 101),
                Map.of("process_id", 102, "type", "A"),
                Map.of("process_id", 103, "type", "B", "region", "EU"),
                Map.of("process_id", 104, "type", "C", "region", "US", "from", "2025-01-01")
        );

        ProcessApiClient client = FeignConfig.createClient(BASE_URL);

        ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

        Semaphore rateLimiter = new Semaphore(REQUESTS_PER_SECOND);
        ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();
        scheduler.scheduleAtFixedRate(() -> {
            int missing = REQUESTS_PER_SECOND - rateLimiter.availablePermits();
            if (missing > 0) rateLimiter.release(missing);
        }, 0, 1, TimeUnit.SECONDS);

        Queue<Map<String, Object>> allResults = new ConcurrentLinkedQueue<>();
        AtomicInteger success = new AtomicInteger();
        AtomicInteger failed = new AtomicInteger();

        List<Future<Map<String, Object>>> futures = new ArrayList<>();

        for (Map<String, Object> params : requests) {
            futures.add(executor.submit(() -> {
                rateLimiter.acquireUninterruptibly();
                return callWithRetry(client, params);
            }));
        }

        for (Future<Map<String, Object>> f : futures) {
            try {
                Map<String, Object> result = f.get(30, TimeUnit.SECONDS);
                if (result != null) {
                    allResults.add(result);
                    success.incrementAndGet();
                } else {
                    failed.incrementAndGet();
                }
            } catch (Exception e) {
                failed.incrementAndGet();
            }
        }

        executor.shutdown();
        executor.awaitTermination(1, TimeUnit.HOURS);
        scheduler.shutdown();

        System.out.println("Finished");
        System.out.println("Success: " + success.get());
        System.out.println("Failed: " + failed.get());
        System.out.println("In-memory records: " + allResults.size());

        // 👉 allResults contains everything in memory
    }

    static Map<String, Object> callWithRetry(ProcessApiClient client,
                                              Map<String, Object> params) {

        for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                return client.getProcess(params);
            } catch (Exception e) {
                System.out.println("Attempt " + attempt + " failed for " + params);
                try { Thread.sleep(500L * attempt); }
                catch (InterruptedException ignored) {}
            }
        }
        return null;
    }
}
Hello,

Regarding the additional field that was added, could you please confirm whether it would be possible to apply an OR condition between fields X and Y on your side and expose the result as a separate exception or derived field in the response?

Please let us know if this is feasible or if there are any constraints.

Thank you.

Just wanted to double-confirm the following points:
The additional fields will be available in the production environment for XYZ by 9th Feb. Please let us know if this timeline still holds.
The data contract is currently pending for data inputs from your end. We request that this be filled and completed by 9th Feb as well, so we can proceed as planned.
Please let us know if anything is required from our side to meet these timelines.
Thanks and regards,
