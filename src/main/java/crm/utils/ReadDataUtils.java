package crm.utils;

import javax.swing.*;
import javax.swing.filechooser.FileNameExtensionFilter;
import java.io.File;

/**
 * @deprecated This class uses Swing JFileChooser which requires GUI environment and is not compatible with containerized deployments.
 * Use REST API endpoints with multipart/form-data file uploads instead.
 * Containers run headless and cannot display GUI dialogs, causing HeadlessException at runtime.
 */
@Deprecated
public class ReadDataUtils {

    /**
     * @deprecated This method uses JFileChooser which requires GUI environment.
     * Not compatible with containerized deployments. Use file upload REST endpoints instead.
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
