# Logo na interface

Arquivo aplicado: Sources/TableGarden/Resources/Branding/logo-sidebar.png.
Original preservado: Sources/TableGarden/Resources/Branding/logo.png.

Edição realizada com a ferramenta integrada image_gen, em modo background-extraction, com transparência ativada. O app carrega o PNG resultante localmente; não usa serviço de imagens em execução.

Prompt: Remove ONLY the outer nearly black rectangular background outside the rounded navy blue square app icon. Make the area outside the rounded square genuinely transparent with clean antialiased edges. Preserve the entire rounded navy square tile and the yellow geometric bee and blue opposing arrows inside it exactly, unchanged geometry colors composition proportions texture. No redesign, no text, no added elements. Output transparent PNG.

## Dock e Finder

O empacotamento agora usa o logo transparente também para gerar AppIcon.icns em todas as resoluções de 16 a 1024 pixels. O símbolo arredondado é centralizado num canvas transparente de 1024 pixels, com corpo de 824 pixels. O script scripts/generate-app-icon.swift normaliza apenas o enquadramento e o tamanho; o desenho original continua preservado. O aplicativo define também applicationIconImage ao iniciar para atualizar seu ícone no Dock.
