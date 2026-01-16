package crm.utils;

import java.io.File;

public class ReadDataUtils {

    public static File ReadFile(String dialogMEssage, String fileExtensionDescription,
                                String... fileExtension) {
        String dataFilePath = System.getenv().getOrDefault("DATA_FILE_PATH", "/data/uploads");
        File file = new File(dataFilePath);
        if (file.exists() && file.isFile()) {
            System.out.println("Using configured file path: " + file.getName());
            return file;
        }
        System.out.println("File not found at configured path: " + dataFilePath);
        return null;
    }

}
