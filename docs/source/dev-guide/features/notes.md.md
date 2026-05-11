# Feature Notes

The `NOTES.md` file is an optional markdown document allowing features to provide additional user-facing information and context that do not fit in the `metadata.yaml` file.

This is the template for the Feature Notes document.
It contains comprehensive usage instructions, details on settings and behavior, and any other relevant information that doesn't fit in the `metadata.yaml` file. Refrain from repeating information that is already covered in the metadata, such as general feature description, option descriptions, and examples that can be automatically generated. Instead, focus on providing additional context, details, limitations, and other important usage notes for users to understand and effectively use the feature, for example:

- Schemas, contrac
- Important considerations for certain combinations of options.
- Platform-specific behavior or limitations.
- Best practices for using the API effectively.
- Troubleshooting tips for common issues or misconfigurations.
- Any other relevant information.

Each file must only contain a collection of level-2 headings and their content (no H1) to ensure they integrate cleanly into the generated feature documentation. Each H2 should represent a distinct topic or aspect of the feature, and can be further organized with subheadings as needed. There are no strict requirements on the content of each section, since it depends on the specific feature; below are some common topics that are often covered in the notes, but feel free to include/exclude any sections as appropriate for the specific feature.

Provide all necessary information for users to understand and effectively use the API, including:

Organize the information in a clear, logical manner with appropriate subheadings, bullet points, and formatting to enhance readability and comprehension, e.g.:

### <Platform Name> Limitations and Workarounds
- Describe any limitations or quirks of the API on this platform.
- Provide any known workarounds or mitigation strategies for these limitations.

The following H2 titles are automatically generated based on the `metadata.yaml` content; do not include them in the notes:

- Example Usage
- Options
- Lifecycle Commands
- Installation Order
- VS Code Extensions

### Supported Installation Methods

Describe the tool installation/setup method(s) supported by the feature and available to users to choose from (e.g. package manager, pre-built binary, build from source, download URL).
For each method, write a subsection as follows:

#### Method Name (e.g. "OS Package Manager", "Binary Download", "Installer Script", "<Name of Tool> Installation")

Shortly describe the method, and any considerations, limitations, or other important information users should be aware of when choosing this method. For example:
- if some platforms are not supported by this method, or have specific quirks or limitations when using it, and how to work around them.
- if there are important differences in behavior or configuration options when using this method.
- if there are any important trade-offs to consider when choosing this method (e.g. simplicity vs flexibility, speed vs reliability, etc.).
- if there are special dependenies or requirements for this method that users should be aware of.

### Version Selection

Describe how users can select the version of the tool to install, if applicable. If the version selection availability or behavior differs based on the installation method or other factors, make sure to clearly explain these differences and any important considerations for users when selecting versions.

### Installation Path

If the installation path configuration availability or behavior differs based on the installation method, target platform, or other factors, make sure to clearly explain these differences and any important considerations for users when specifying installation paths. If there are any important limitations or caveats related to installation paths (e.g. certain platforms not supporting custom installation paths, or specific requirements for PATH addition when using custom paths), make sure to clearly explain them and provide any necessary workarounds or mitigation strategies.

### User Installation

Describe how users can specify the target user(s) for the installation, if applicable (e.g. root vs non-root, specific user names, multiple users). If the installation can only be done by the root user, make sure to clearly explain this limitation and provide any necessary workarounds or mitigation strategies for users who want to install for non-root users. If there are any important considerations or limitations related to user targeting (e.g. certain platforms having specific requirements or quirks when installing for non-root users), make sure to clearly explain them and provide any necessary workarounds or mitigation strategies.
