package crm.utils;

import javax.swing.*;
import javax.swing.filechooser.FileNameExtensionFilter;
import java.io.File;

/**
 * @deprecated This class uses GUI components (JFileChooser) which are incompatible with containerized environments.
 * For file uploads in containers, use REST API endpoints with MultipartFile instead.
 * This class will cause HeadlessException in container environments.
 */
@Deprecated
public class ReadDataUtils {

    /**
     * @deprecated Use REST API file upload endpoints with Spring's MultipartFile instead.
     * This method uses JFileChooser which requires GUI/X11 and will not work in containers.
     */
    @Deprecated
    public static File ReadFile(String dialogMEssage, JFrame parent, String fileExtensionDescription,
                                String... fileExtension) {
        JFileChooser chooser = new JFileChooser();
        FileNameExtensionFilter filter = new FileNameExtensionFilter(fileExtensionDescription, fileExtension);
        chooser.setFileFilter(filter);
        int returnVal = chooser.showOpenDialog(parent);
        if (returnVal == JFileChooser.APPROVE_OPTION) {
            System.out.println("You chose to open this file: " + chooser.getSelectedFile().getName());
            return chooser.getSelectedFile();
        }
        return null;
    }

}
