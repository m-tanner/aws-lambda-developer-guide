package example;

import com.amazonaws.regions.Regions;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import com.google.gson.Gson;

public class Util {

  public static void logEnvironment(Object event, Context context, Gson gson) {
    LambdaLogger logger = context.getLogger();
    // log execution details
    logger.log("ENVIRONMENT VARIABLES: " + gson.toJson(System.getenv()));
    logger.log("CONTEXT: " + gson.toJson(context));
    // log event details
    logger.log("EVENT: " + gson.toJson(event));
    logger.log("EVENT TYPE: " + event.getClass().toString());
  }

  public static String writeFileToS3(String key, String content) {
    String bucketName = System.getenv("S3_BUCKET_NAME");
    AmazonS3 s3Client = AmazonS3ClientBuilder
        .standard()
        .withRegion(Regions.GovCloud)
        .build();
    s3Client.putObject(bucketName, key, content);
    return s3Client.getUrl(bucketName, key).toExternalForm();
  }
}