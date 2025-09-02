$ = (sel) -> document.querySelector sel

inputItems = ['text', 'color', 'alpha', 'angle', 'space', 'size', 'font-family', 'watermark-position']
input = {}

image = $ '#image'
graph = $ '#graph'
refresh = $ '#refresh'
autoRefresh = $ '#auto-refresh'
textWatermarkRadio = $ '#text-watermark'
imageWatermarkRadio = $ '#image-watermark'
textWatermarkOptions = $ '#text-watermark-options'
imageWatermarkOptions = $ '#image-watermark-options'
watermarkImage = $ '#watermark-image'
pdfPagesContainer = $ '#pdf-pages-container'
pdfPagesDiv = $ '#pdf-pages'
selectAllPagesBtn = $ '#select-all-pages'
clearSelectionBtn = $ '#clear-selection'
previewSelectedPagesBtn = $ '#preview-selected-pages'
downloadSelectedPagesBtn = $ '#download-selected-pages'
pdfPageCountSpan = $ '#pdf-page-count'
selectedPageCountSpan = $ '#selected-page-count'

file = null
originalFileType = null
originalFileName = null
watermarkImageFile = null
canvas = null
textCtx = null
redraw = null
watermarkType = 'text'
pdfDocument = null
selectedPages = new Set()
processedCanvases = new Map()  # 使用Map存储处理过的画布，key为页码
isProcessing = false
currentPDFPages = []  # 存储当前PDF的页面数据用于实时预览
updateTimeout = null  # 用于节流预览更新
lastUpdateTime = 0   # 上次更新时间
isUpdatingPreview = false  # 防止递归调用的标志

# 应用状态对象
state = {
    currentPDF: null
    textWatermark: false
    imageWatermark: false
}

# 自动更新预览区域（简化版，使用直接的延迟更新和防递归标志）
updatePreviewArea = ->
    
    # 如果已经在更新中，则忽略此次调用
    if isUpdatingPreview
        return
    
    # 清除之前的延迟更新
    clearTimeout(updateTimeout) if updateTimeout
    
    # 设置新的延迟更新 - 100ms的短延迟保证响应性
    updateTimeout = setTimeout(->
        # 设置更新标志，防止递归调用
        isUpdatingPreview = true
        
        try
            # 清空之前的预览
            graph.innerHTML = '<div class="preview-container"></div>'
            previewContainer = graph.querySelector('.preview-container')
            
            # 如果没有选中页面，显示提示
            if selectedPages.size == 0
                emptyMessage = document.createElement 'div'
                emptyMessage.className = 'empty-preview-message'
                emptyMessage.innerHTML = '<i class="fas fa-info-circle"></i> 请在PDF页面管理区选择要添加水印的页面'
                previewContainer.appendChild emptyMessage
                
                # 完成更新，重置标志
                isUpdatingPreview = false
                return
            
            # 显示正在加载的提示
            loadingMessage = document.createElement 'div'
            loadingMessage.className = 'loading-preview-message'
            loadingMessage.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 正在生成预览...'
            previewContainer.appendChild loadingMessage
            
            # 获取排序后的页面数组
            pagesArray = Array.from(selectedPages).sort((a, b) -> a - b)
            processedCount = 0
            
            # 强制清除缓存，确保每次都使用最新的水印设置
            if processedCanvases?
                processedCanvases.clear()
            
            # 渲染选中的页面
            renderPreviewPages(pagesArray, previewContainer, processedCount, loadingMessage, ->
                # 在渲染完成后重置标志
                isUpdatingPreview = false
            )
        catch err
            # 确保错误情况下也重置标志
            isUpdatingPreview = false
            console.error "预览更新出错:", err
    , 100)

# 渲染预览页面
renderPreviewPages = (pagesArray, previewContainer, processedCount, loadingMessage, onComplete) ->
    if processedCount >= pagesArray.length
        # 所有页面处理完成，移除加载提示
        loadingMessage?.remove()
        # 调用完成回调
        onComplete?()
        return
    
    pageNum = pagesArray[processedCount]
    
    # 确保PDF已加载
    return unless state.currentPDF?
    
    state.currentPDF.getPage(pageNum).then (page) ->
        scale = 1.5  # 预览质量
        viewport = page.getViewport({ scale: scale })
        
        pageCanvas = document.createElement 'canvas'
        pageCanvas.width = viewport.width
        pageCanvas.height = viewport.height
        context = pageCanvas.getContext '2d'
        
        renderContext = 
            canvasContext: context
            viewport: viewport
        
        page.render(renderContext).promise.then ->
            
            # 应用水印
            if watermarkType == 'text' and input.text.value
                drawTextWatermarkOnCanvas pageCanvas, context
            else if watermarkType == 'image' and watermarkImageFile?
                drawImageWatermarkOnCanvas pageCanvas, context
            else
            
            # 添加到预览容器
            pagePreviewDiv = document.createElement 'div'
            pagePreviewDiv.className = 'preview-page'
            pagePreviewDiv.dataset.pageNum = pageNum
            
            pageTitle = document.createElement 'h5'
            pageTitle.textContent = "第 #{pageNum} 页"
            pagePreviewDiv.appendChild pageTitle
            
            # 设置canvas样式
            pageCanvas.className = 'canvas-preview'
            pageCanvas.style.maxWidth = '100%'
            pageCanvas.style.border = '1px solid #ddd'
            pageCanvas.style.borderRadius = '4px'
            pagePreviewDiv.appendChild pageCanvas
            
            # 添加点击下载功能
            pageCanvas.addEventListener 'click', ->
                downloadFormat = document.querySelector('input[name="download-format"]:checked')?.value || 'png'
                
                link = document.createElement 'a'
                link.download = generateFileName(pageNum, true)
                
                if downloadFormat == 'png'
                    imageData = pageCanvas.toDataURL 'image/png'
                else
                    imageData = pageCanvas.toDataURL "image/#{downloadFormat}", 0.95
                
                blob = dataURItoBlob imageData
                link.href = URL.createObjectURL blob
                document.body.appendChild link
                link.click()
                document.body.removeChild link
            
            # 将预览添加到容器
            previewContainer.appendChild pagePreviewDiv
            
            # 处理下一页
            processedCount++
            renderPreviewPages(pagesArray, previewContainer, processedCount, loadingMessage, onComplete)
            
        .catch (error) ->
            console.error "预览渲染第#{pageNum}页失败:", error
            processedCount++
            renderPreviewPages(pagesArray, previewContainer, processedCount, loadingMessage, onComplete)
    
    .catch (error) ->
        console.error "获取第#{pageNum}页失败:", error
        processedCount++
        renderPreviewPages(pagesArray, previewContainer, processedCount, loadingMessage, onComplete)

# 更新范围值显示
updateRangeValues = ->
    ($ '#alpha-value').textContent = Math.round(input.alpha.value * 100) + '%'
    ($ '#angle-value').textContent = input.angle.value + '°'
    ($ '#space-value').textContent = input.space.value + 'x'
    ($ '#size-value').textContent = input.size.value + 'x'

# 更新选中页面计数
updateSelectedPageCount = ->
    selectedPageCountSpan.textContent = "已选择 #{selectedPages.size} 页"

# 检查PDF.js库是否正确加载
checkPDFJSLibrary = ->
    if typeof pdfjsLib is 'undefined'
        console.error 'PDF.js 库未加载'
        return false
    
    if typeof pdfjsLib.getDocument isnt 'function'
        console.error 'PDF.js 库加载不完整'
        return false
    
    return true

dataURItoBlob = (dataURI) ->
    binStr = atob (dataURI.split ',')[1]
    len = binStr.length
    arr = new Uint8Array len

    for i in [0..len - 1]
        arr[i] = binStr.charCodeAt i
    new Blob [arr], type: 'image/png'


generateFileName = (pageNum = null, keepOriginalFormat = false) ->
    pad = (n) -> if n < 10 then '0' + n else n
    d = new Date
    timestamp = '' + d.getFullYear() + '-' + (pad d.getMonth() + 1) + '-' + (pad d.getDate()) + '_' + \
        (pad d.getHours()) + (pad d.getMinutes()) + (pad d.getSeconds())
    
    if keepOriginalFormat and originalFileName
        # 保持原始文件名和格式
        baseName = originalFileName.replace(/\.[^/.]+$/, "")
        extension = originalFileName.match(/\.[^/.]+$/)?[0] or '.png'
        if pageNum?
            return "#{baseName}_page#{pageNum}_watermarked_#{timestamp}#{extension}"
        else
            return "#{baseName}_watermarked_#{timestamp}#{extension}"
    else
        # 使用PNG格式
        if pageNum?
            return "page_#{pageNum}_watermarked_#{timestamp}.png"
        else
            return "watermarked_#{timestamp}.png"

# 根据文件类型创建对应的blob
createFileBlob = (canvas, format = 'png') ->
    if format.toLowerCase() == 'pdf'
        return createPDFBlob canvas
    else
        dataURI = canvas.toDataURL "image/#{format}", 0.95
        return dataURItoBlob dataURI

# 创建PDF格式的blob
createPDFBlob = (canvasArray) ->
    # 检查jsPDF是否可用
    jsPDFLib = window.jsPDF || window.jspdf?.jsPDF
    return null unless jsPDFLib?
    
    if not Array.isArray(canvasArray)
        canvasArray = [canvasArray]
    
    return null if canvasArray.length == 0
    
    # 使用第一个canvas确定PDF尺寸
    firstCanvas = canvasArray[0]
    return null unless firstCanvas?
    
    try
        pdf = new jsPDFLib({
            orientation: if firstCanvas.width > firstCanvas.height then 'landscape' else 'portrait'
            unit: 'px'
            format: [firstCanvas.width, firstCanvas.height]
        })
        
        for canvas, index in canvasArray
            if index > 0
                pdf.addPage([canvas.width, canvas.height])
            
            imgData = canvas.toDataURL 'image/jpeg', 0.95
            pdf.addImage imgData, 'JPEG', 0, 0, canvas.width, canvas.height
        
        return pdf.output 'blob'
    catch error
        console.error 'PDF生成失败:', error
        return null


readFile = ->
    return if not file?
    
    # 记录原始文件信息
    originalFileType = file.type
    originalFileName = file.name

    # 检查文件类型
    if file.type == 'application/pdf'
        readPDFFile()
    else if file.type.startsWith 'image/'
        readImageFile()
    else
        alert '仅支持图片文件 (png, jpg, gif, webp, bmp, svg) 和 PDF 文件'

readImageFile = ->
    fileReader = new FileReader

    fileReader.onload = ->
        img = new Image
        img.onload = ->
            setupCanvas img
        img.onerror = ->
            hideMobileLoadingTip()
            alert '图片文件格式不支持或已损坏'
        img.src = fileReader.result

    fileReader.onerror = ->
        hideMobileLoadingTip()
        alert '图片文件读取失败，请检查文件是否损坏'

    fileReader.readAsDataURL file

readPDFFile = ->
    if not checkPDFJSLibrary()
        alert 'PDF.js 库未正确加载，请刷新页面重试'
        return
    
    fileReader = new FileReader
    fileReader.onload = ->
        try
            loadingTask = pdfjsLib.getDocument(fileReader.result)
            loadingTask.promise.then (pdf) ->
                state.currentPDF = pdf
                pdfDocument = pdf
                numPages = pdf.numPages
                
                # 清空之前的数据
                currentPDFPages = []
                selectedPages.clear()
                
                # 显示PDF页面容器
                pdfPagesContainer.style.display = 'block'
                pdfPagesDiv.innerHTML = ''
                
                # 更新页面计数
                pdfPageCountSpan.textContent = "共 #{numPages} 页"
                updateSelectedPageCount()
                
                # 首先渲染第一页到主预览区域
                pdf.getPage(1).then (firstPage) ->
                    scale = 1.0  # 主预览使用更大的缩放
                    viewport = firstPage.getViewport({ scale: scale })
                    
                    # 创建主预览canvas
                    canvas = document.createElement 'canvas'
                    canvas.width = viewport.width
                    canvas.height = viewport.height
                    canvas.className = 'canvas-preview'
                    
                    ctx = canvas.getContext '2d'
                    
                    renderContext = 
                        canvasContext: ctx
                        viewport: viewport
                    
                    firstPage.render(renderContext).promise.then ->
                        # 设置全局变量供水印函数使用
                        window.canvas = canvas
                        window.textCtx = ctx
                        window.originalImage = null  # PDF没有原始图片
                        
                        # 创建重绘函数
                        window.redraw = ->
                            # 重新渲染PDF页面
                            firstPage.render(renderContext).promise.then ->
                                # 重新应用水印
                                if watermarkType == 'text' and input.text.value
                                    drawTextWatermarkOnCanvas canvas, ctx
                                else if watermarkType == 'image' and watermarkImageFile?
                                    drawImageWatermarkOnCanvas canvas, ctx
                        
                        # 应用当前水印设置
                        if watermarkType == 'text' and input.text.value
                            drawTextWatermarkOnCanvas canvas, ctx
                        else if watermarkType == 'image' and watermarkImageFile?
                            drawImageWatermarkOnCanvas canvas, ctx
                        
                        # 显示在主预览区域
                        graph.innerHTML = ''
                        
                        # 添加页面标题
                        pageTitle = document.createElement 'h3'
                        pageTitle.textContent = "PDF预览 - 第1页"
                        pageTitle.style.textAlign = 'center'
                        pageTitle.style.margin = '10px 0'
                        pageTitle.id = 'pdf-preview-title'
                        graph.appendChild pageTitle
                        
                        graph.appendChild canvas
                        
                        # 移动端隐藏加载提示（PDF处理完成）
                        if isMobile()
                            setTimeout hideMobileLoadingTip, 300
                        
                        # 添加点击下载功能
                        canvas.addEventListener 'click', ->
                            downloadFormat = document.querySelector('input[name="download-format"]:checked')?.value || 'png'
                            
                            link = document.createElement 'a'
                            link.download = generateFileName(1, true)
                            
                            if downloadFormat == 'png'
                                imageData = canvas.toDataURL 'image/png'
                            else
                                imageData = canvas.toDataURL "image/#{downloadFormat}", 0.95
                            
                            blob = dataURItoBlob imageData
                            link.href = URL.createObjectURL blob
                            document.body.appendChild link
                            link.click()
                            document.body.removeChild link
                
                # 添加加载提示
                loadingDiv = document.createElement 'div'
                loadingDiv.id = 'pdf-loading'
                loadingDiv.style.textAlign = 'center'
                loadingDiv.style.padding = '20px'
                loadingDiv.style.color = '#666'
                loadingDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 正在生成页面预览...'
                pdfPagesDiv.appendChild loadingDiv
                
                # 创建页面预览 - 使用队列确保顺序
                renderPagesSequentially pdf, numPages
                    
            .catch (error) ->
                hideMobileLoadingTip()
                console.error 'PDF加载错误:', error
                console.error 'Error details:', error.name, error.message
                if error.name == 'InvalidPDFException'
                    alert 'PDF文件格式无效或已损坏'
                else if error.name == 'MissingPDFException'
                    alert 'PDF文件内容缺失'
                else if error.name == 'UnexpectedResponseException'
                    alert 'PDF文件读取失败，可能文件过大或格式不支持'
                else
                    alert "PDF文件加载失败: #{error.message || '未知错误'}"
        catch generalError
            hideMobileLoadingTip()
            console.error 'PDF处理异常:', generalError
            alert "PDF处理失败: #{generalError.message || '未知错误'}"
    
    fileReader.onerror = ->
        hideMobileLoadingTip()
        console.error 'PDF文件读取失败'
        alert '文件读取失败，请检查文件是否损坏或过大'
    
    fileReader.readAsArrayBuffer file

# 顺序渲染PDF页面，避免并发问题
renderPagesSequentially = (pdf, totalPages) ->
    renderedCount = 0
    
    renderNextPage = (pageNum) ->
        if pageNum > totalPages
            # 所有页面渲染完成，移除加载提示
            loadingDiv = document.getElementById 'pdf-loading'
            loadingDiv?.remove()
            
            # 强制垃圾回收（如果可能）
            if window.gc?
                window.gc()
            
            # 自动更新预览区域
            updatePreviewArea()
            
            return
        
        createPagePreview pageNum, pdf, ->
            renderedCount++
            # 更新加载进度
            loadingDiv = document.getElementById 'pdf-loading'
            if loadingDiv
                progress = Math.round((renderedCount / totalPages) * 100)
                loadingDiv.innerHTML = "<i class='fas fa-spinner fa-spin'></i> 正在生成页面预览... #{progress}%"
            
            # 渲染下一页，添加适当的延迟
            setTimeout ->
                renderNextPage pageNum + 1
            , 100  # 增加延迟确保每页完全渲染完成
    
    renderNextPage 1

createPagePreview = (pageNum, pdf, callback = null) ->
    # 添加重试机制
    attemptRender = (retryCount = 0) ->
        pdf.getPage(pageNum).then (page) ->
            scale = 0.3  # 预览缩放
            viewport = page.getViewport({ scale: scale })
            
            # 为每个页面创建独立的容器和canvas
            pageDiv = document.createElement 'div'
            pageDiv.className = 'pdf-page'
            pageDiv.dataset.pageNum = pageNum
            
            # 创建独立的canvas
            pageCanvas = document.createElement 'canvas'
            pageCanvas.width = viewport.width
            pageCanvas.height = viewport.height
            pageCanvas.style.maxWidth = '100%'
            pageCanvas.style.borderRadius = '4px'
            
            # 确保canvas尺寸正确
            if pageCanvas.width == 0 or pageCanvas.height == 0
                console.warn "第 #{pageNum} 页canvas尺寸异常，尝试重新渲染"
                if retryCount < 2
                    setTimeout ->
                        attemptRender retryCount + 1
                    , 200
                    return
                else
                    throw new Error "Canvas尺寸异常"
            
            # 获取独立的渲染上下文
            pageContext = pageCanvas.getContext '2d'
            
            renderContext = 
                canvasContext: pageContext
                viewport: viewport
            
            # 渲染PDF页面到独立的canvas
            renderTask = page.render(renderContext)
            renderTask.promise.then ->
                # 验证渲染结果
                imageData = pageContext.getImageData(0, 0, pageCanvas.width, pageCanvas.height)
                isBlank = true
                for i in [0...imageData.data.length] by 4
                    if imageData.data[i] != 255 or imageData.data[i+1] != 255 or imageData.data[i+2] != 255
                        isBlank = false
                        break
                
                if isBlank and retryCount < 2
                    console.warn "第 #{pageNum} 页渲染为空白，尝试重新渲染"
                    setTimeout ->
                        attemptRender retryCount + 1
                    , 200
                    return
                
                # 确保渲染完成后再添加到DOM
                pageDiv.appendChild pageCanvas
                
                pageNumber = document.createElement 'div'
                pageNumber.className = 'page-number'
                pageNumber.textContent = "第 #{pageNum} 页"
                pageDiv.appendChild pageNumber
                
                # 添加点击事件监听器
                pageDiv.addEventListener 'click', ->
                    if selectedPages.has pageNum
                        selectedPages.delete pageNum
                        pageDiv.classList.remove 'selected'
                    else
                        selectedPages.add pageNum
                        pageDiv.classList.add 'selected'
                    
                    updateSelectedPageCount()
                    
                    # 自动更新预览区域
                    updatePreviewArea()
                
                # 将完成的页面插入到正确位置（保持页面顺序）
                insertPageInOrder pageDiv, pageNum
                
                # 调用回调函数
                callback?()
                
            .catch (error) ->
                console.error "第 #{pageNum} 页渲染失败:", error
                if retryCount < 2
                    setTimeout ->
                        attemptRender retryCount + 1
                    , 500
                else
                    createErrorPlaceholder pageNum, pageDiv, callback
                    
        .catch (error) ->
            console.error "获取第 #{pageNum} 页失败:", error
            if retryCount < 2
                setTimeout ->
                    attemptRender retryCount + 1
                , 500
            else
                pageDiv = document.createElement 'div'
                pageDiv.className = 'pdf-page'
                pageDiv.dataset.pageNum = pageNum
                createErrorPlaceholder pageNum, pageDiv, callback
    
    attemptRender()

# 创建错误占位符
createErrorPlaceholder = (pageNum, pageDiv, callback) ->
    pageDiv.innerHTML = "<div style='padding: 20px; text-align: center; color: #999; border: 2px dashed #ddd; border-radius: 4px;'>第 #{pageNum} 页<br><small>渲染失败</small><br><button onclick='location.reload()' style='margin-top:5px; padding:2px 8px; font-size:10px;'>重新加载</button></div>"
    
    pageNumber = document.createElement 'div'
    pageNumber.className = 'page-number'
    pageNumber.textContent = "第 #{pageNum} 页"
    pageDiv.appendChild pageNumber
    
    pageDiv.addEventListener 'click', ->
        if selectedPages.has pageNum
            selectedPages.delete pageNum
            pageDiv.classList.remove 'selected'
        else
            selectedPages.add pageNum
            pageDiv.classList.add 'selected'
        
        updateSelectedPageCount()
        
        # 自动更新预览区域
        updatePreviewArea()
    
    insertPageInOrder pageDiv, pageNum
    callback?()

# 重新渲染PDF页面（用于实时预览）
rerenderPDFPages = ->
    return unless currentPDFPages.length > 0
    
    for pageInfo in currentPDFPages
        pageDiv = document.querySelector("[data-page-num='#{pageInfo.pageNum}']")
        continue unless pageDiv?
        
        # 重新渲染页面
        rerenderSinglePDFPage(pageInfo, pageDiv)

# 重新渲染单个PDF页面
rerenderSinglePDFPage = (pageInfo, pageDiv) ->
    try
        scale = 0.3  # 预览缩放
        viewport = pageInfo.page.getViewport({ scale: scale })
        
        # 创建新的canvas
        newCanvas = document.createElement 'canvas'
        newCanvas.width = viewport.width
        newCanvas.height = viewport.height
        newCanvas.style.maxWidth = '100%'
        newCanvas.style.borderRadius = '4px'
        
        newContext = newCanvas.getContext '2d'
        
        renderContext = 
            canvasContext: newContext
            viewport: viewport
        
        # 渲染PDF页面
        pageInfo.page.render(renderContext).promise.then ->
            # 应用水印
            if state.textWatermark or state.imageWatermark
                applyWatermarkToPDFPage(newCanvas, newContext)
            
            # 替换现有的canvas
            oldCanvas = pageDiv.querySelector('canvas')
            if oldCanvas
                pageDiv.replaceChild(newCanvas, oldCanvas)
            else
                pageDiv.insertBefore(newCanvas, pageDiv.firstChild)
        
        .catch (error) ->
            console.error "重新渲染第 #{pageInfo.pageNum} 页失败:", error
    catch error
        console.error "重新渲染第 #{pageInfo.pageNum} 页出错:", error

# 为PDF页面应用水印
applyWatermarkToPDFPage = (canvas, context) ->
    if state.textWatermark and input.text.value
        drawTextWatermarkOnCanvas(canvas, context)
    
    if state.imageWatermark and watermarkImageFile?
        drawImageWatermarkOnCanvas(canvas, context)

# 应用文本水印到PDF页面
applyTextWatermark = (canvas, context) ->
    drawTextWatermarkOnCanvas(canvas, context)

# 应用图片水印到PDF页面  
applyImageWatermark = (canvas, context) ->
    drawImageWatermarkOnCanvas(canvas, context)

# 按页面顺序插入页面元素
insertPageInOrder = (newPageDiv, pageNum) ->
    loadingDiv = document.getElementById 'pdf-loading'
    
    # 找到正确的插入位置
    existingPages = pdfPagesDiv.querySelectorAll('.pdf-page')
    insertBefore = null
    
    for existingPage in existingPages
        existingPageNum = parseInt(existingPage.dataset.pageNum)
        if existingPageNum > pageNum
            insertBefore = existingPage
            break
    
    if insertBefore
        pdfPagesDiv.insertBefore newPageDiv, insertBefore
    else if loadingDiv
        pdfPagesDiv.insertBefore newPageDiv, loadingDiv
    else
        pdfPagesDiv.appendChild newPageDiv

# 预览选中的页面
previewSelectedPages = ->
    if selectedPages.size == 0
        alert '请先选择要预览的页面'
        return
    
    if isProcessing
        alert '正在处理中，请稍候...'
        return
    
    isProcessing = true
    graph.innerHTML = '<div class="preview-container"></div>'
    previewContainer = graph.querySelector('.preview-container')
    
    # 创建进度条
    progressBar = document.createElement 'div'
    progressBar.className = 'progress-bar'
    progressFill = document.createElement 'div'
    progressFill.className = 'progress-fill'
    progressBar.appendChild progressFill
    previewContainer.appendChild progressBar
    
    pagesArray = Array.from(selectedPages).sort((a, b) -> a - b)
    processedCount = 0
    
    processNextPage = (index) ->
        if index >= pagesArray.length
            # 所有页面处理完成
            progressBar.style.display = 'none'
            isProcessing = false
            return
        
        pageNum = pagesArray[index]
        
        # 更新进度
        progress = ((index + 1) / pagesArray.length) * 100
        progressFill.style.width = "#{progress}%"
        
        pdfDocument.getPage(pageNum).then (page) ->
            scale = 1.5  # 预览质量
            viewport = page.getViewport({ scale: scale })
            
            pageCanvas = document.createElement 'canvas'
            pageCanvas.width = viewport.width
            pageCanvas.height = viewport.height
            context = pageCanvas.getContext '2d'
            
            renderContext = 
                canvasContext: context
                viewport: viewport
            
            page.render(renderContext).promise.then ->
                # 直接应用水印，不需要Image对象
                if watermarkType == 'text' and input.text.value
                    drawTextWatermarkOnCanvas pageCanvas, context
                else if watermarkType == 'image' and watermarkImageFile?
                    drawImageWatermarkOnCanvas pageCanvas, context
                
                # 添加到预览容器
                pagePreviewDiv = document.createElement 'div'
                pagePreviewDiv.className = 'preview-page'
                pagePreviewDiv.dataset.pageNum = pageNum
                
                pageTitle = document.createElement 'h5'
                pageTitle.textContent = "第 #{pageNum} 页"
                pagePreviewDiv.appendChild pageTitle
                
                # 设置canvas样式
                pageCanvas.className = 'canvas-preview'
                pageCanvas.style.maxWidth = '100%'
                pageCanvas.style.border = '1px solid #ddd'
                pageCanvas.style.borderRadius = '4px'
                pagePreviewDiv.appendChild pageCanvas
                
                # 添加点击下载功能
                pageCanvas.addEventListener 'click', ->
                    downloadFormat = document.querySelector('input[name="download-format"]:checked')?.value || 'png'
                    
                    link = document.createElement 'a'
                    link.download = generateFileName(pageNum, true)
                    
                    if downloadFormat == 'png'
                        imageData = pageCanvas.toDataURL 'image/png'
                    else
                        imageData = pageCanvas.toDataURL "image/#{downloadFormat}", 0.95
                    
                    blob = dataURItoBlob imageData
                    link.href = URL.createObjectURL blob
                    document.body.appendChild link
                    link.click()
                    document.body.removeChild link
                
                previewContainer.appendChild pagePreviewDiv
                
                # 处理下一页
                processNextPage index + 1
                
            .catch (error) ->
                console.error "渲染第#{pageNum}页失败:", error
                processNextPage index + 1
                
        .catch (error) ->
            console.error "获取第#{pageNum}页失败:", error
            processNextPage index + 1
    
    processNextPage 0

# 下载选中的页面
downloadSelectedPages = ->
    if selectedPages.size == 0
        alert '请先选择要下载的页面'
        return
    
    if isProcessing
        alert '正在处理中，请稍候...'
        return
    
    downloadFormat = document.querySelector('input[name="download-format"]:checked').value
    
    if downloadFormat == 'pdf'
        downloadAsPDF()
    else
        downloadAsImages()

# 下载为PDF格式
downloadAsPDF = ->
    
    
    # 检查jsPDF是否可用
    jsPDFLib = window.jsPDF || window.jspdf?.jsPDF
    
    
    if not jsPDFLib?
        alert 'PDF生成库未加载，请刷新页面重试'
        return
    
    isProcessing = true
    pagesArray = Array.from(selectedPages).sort((a, b) -> a - b)
    processedCanvases.clear() # 清除旧缓存
    
    
    
    processNextPage = (index) ->
        
        
        if index >= pagesArray.length
            
            # 创建PDF
            if processedCanvases.size > 0
                try
                    pdfBlob = createPDFBlob Array.from(processedCanvases.values())
                    
                    
                    if pdfBlob
                        link = document.createElement 'a'
                        link.download = generateFileName(null, true).replace(/\.[^/.]+$/, '.pdf')
                        link.href = URL.createObjectURL pdfBlob
                        document.body.appendChild link
                        link.click()
                        document.body.removeChild link
                        
                    else
                        alert 'PDF生成失败'
                        console.error 'PDF blob生成失败'
                catch error
                    console.error 'PDF生成出错:', error
                    alert "PDF生成失败: #{error.message}"
            else
                alert '没有页面可以下载'
                console.warn '没有处理的canvas'
            isProcessing = false
            return
        
        pageNum = pagesArray[index]
        
        
        state.currentPDF.getPage(pageNum).then (page) ->
            
            scale = 2.0  # 高质量
            viewport = page.getViewport({ scale: scale })
            
            pageCanvas = document.createElement 'canvas'
            pageCanvas.width = viewport.width
            pageCanvas.height = viewport.height
            context = pageCanvas.getContext '2d'
            
            renderContext = 
                canvasContext: context
                viewport: viewport
            
            page.render(renderContext).promise.then ->
                
                # 应用水印
                if watermarkType == 'text' and input.text.value
                    
                    drawTextWatermarkOnCanvas pageCanvas, context
                else if watermarkType == 'image' and watermarkImageFile?
                    
                    drawImageWatermarkOnCanvas pageCanvas, context
                
                processedCanvases.set(pageNum, pageCanvas)
                
                
                # 延迟处理下一页
                setTimeout ->
                    processNextPage index + 1
                , 100
                
            .catch (error) ->
                console.error "渲染第#{pageNum}页失败:", error
                processNextPage index + 1
                
        .catch (error) ->
            console.error "获取第#{pageNum}页失败:", error
            processNextPage index + 1
    
    processNextPage 0

# 下载为图片格式
downloadAsImages = ->
    isProcessing = true
    pagesArray = Array.from(selectedPages).sort((a, b) -> a - b)
    downloadDelay = 500  # 每次下载间隔500ms
    
    processNextPage = (index) ->
        if index >= pagesArray.length
            isProcessing = false
            return
        
        pageNum = pagesArray[index]
        
        state.currentPDF.getPage(pageNum).then (page) ->
            scale = 2.0  # 高质量
            viewport = page.getViewport({ scale: scale })
            
            pageCanvas = document.createElement 'canvas'
            pageCanvas.width = viewport.width
            pageCanvas.height = viewport.height
            context = pageCanvas.getContext '2d'
            
            renderContext = 
                canvasContext: context
                viewport: viewport
            
            page.render(renderContext).promise.then ->
                # 应用水印
                if watermarkType == 'text' and input.text.value
                    drawTextWatermarkOnCanvas pageCanvas, context
                else if watermarkType == 'image' and watermarkImageFile?
                    drawImageWatermarkOnCanvas pageCanvas, context
                
                # 下载当前页面
                downloadFormat = document.querySelector('input[name="download-format"]:checked').value
                
                link = document.createElement 'a'
                link.download = generateFileName(pageNum, false)
                
                if downloadFormat == 'png'
                    imageData = pageCanvas.toDataURL 'image/png'
                else
                    imageData = pageCanvas.toDataURL "image/#{downloadFormat}", 0.95
                
                blob = dataURItoBlob imageData
                link.href = URL.createObjectURL blob
                document.body.appendChild link
                link.click()
                document.body.removeChild link
                
                # 延迟处理下一页
                setTimeout ->
                    processNextPage index + 1
                , downloadDelay
                
            .catch (error) ->
                console.error "渲染第#{pageNum}页失败:", error
                setTimeout ->
                    processNextPage index + 1
                , downloadDelay
                
        .catch (error) ->
            console.error "获取第#{pageNum}页失败:", error
            setTimeout ->
                processNextPage index + 1
            , downloadDelay
    
    processNextPage 0

setupCanvas = (img, pageNum = null) ->
    canvas = document.createElement 'canvas'
    canvas.width = img.width
    canvas.height = img.height
    canvas.className = 'canvas-preview'
    textCtx = null
    
    ctx = canvas.getContext '2d'
    ctx.drawImage img, 0, 0

    redraw = ->
        ctx.clearRect 0, 0, canvas.width, canvas.height
        ctx.drawImage img, 0, 0
    
    if watermarkType == 'text'
        drawText()
    else
        drawImageWatermark()

    graph.innerHTML = ''
    
    if pageNum?
        pageTitle = document.createElement 'h3'
        pageTitle.textContent = "第 #{pageNum} 页预览"
        pageTitle.style.textAlign = 'center'
        pageTitle.style.margin = '10px 0'
        graph.appendChild pageTitle
    
    graph.appendChild canvas

    # 移动端隐藏加载提示（图片处理完成）
    if isMobile()
        setTimeout hideMobileLoadingTip, 300

    canvas.addEventListener 'click', ->
        # 确定下载格式
        downloadFormat = 'png'  # 默认PNG
        if originalFileType?.startsWith('image/')
            # 如果原始文件是图片，尝试保持格式
            switch originalFileType
                when 'image/jpeg' then downloadFormat = 'jpeg'
                when 'image/webp' then downloadFormat = 'webp'
                when 'image/gif' then downloadFormat = 'gif'
                else downloadFormat = 'png'
        
        link = document.createElement 'a'
        link.download = generateFileName(pageNum, true)
        
        if downloadFormat == 'png'
            imageData = canvas.toDataURL 'image/png'
            blob = dataURItoBlob imageData
        else
            imageData = canvas.toDataURL "image/#{downloadFormat}", 0.95
            blob = dataURItoBlob imageData
        
        link.href = URL.createObjectURL blob
        document.body.appendChild link
        link.click()
        document.body.removeChild link
    

makeStyle = ->
    match = input.color.value.match /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i

    'rgba(' + (parseInt match[1], 16) + ',' + (parseInt match[2], 16) + ',' \
         + (parseInt match[3], 16) + ',' + input.alpha.value + ')'


getFontFamily = ->
    fontFamily = input['font-family'].value
    switch fontFamily
        when 'system'
            '-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif'
        when 'serif'
            '"Times New Roman",Times,"宋体",SimSun,"Times",serif'
        when 'sans-serif'
            'Arial,"Helvetica Neue",Helvetica,"黑体",SimHei,"Arial",sans-serif'
        when 'monospace'
            '"Courier New",Courier,"等宽字体","Consolas","Monaco",monospace'
        when 'source-han-sans'
            '"Source Han Sans","思源黑体","Noto Sans CJK","Microsoft YaHei",sans-serif'
        when 'source-han-serif'
            '"Source Han Serif","思源宋体","Noto Serif CJK","SimSun",serif'
        when 'noto-sans'
            '"Noto Sans","Arial","Helvetica",sans-serif'
        when 'roboto'
            '"Roboto","Arial","Helvetica",sans-serif'
        else
            fontFamily + ',sans-serif'

# 刷新多页预览
refreshMultiPagePreview = ->
    previewContainer = graph.querySelector('.preview-container')
    return unless previewContainer?
    
    # 获取所有预览页面元素
    previewPages = previewContainer.querySelectorAll('.preview-page')
    return unless previewPages.length > 0
    
    # 遍历所有预览页面并重新应用水印
    for pageDiv in previewPages
        pageNum = parseInt pageDiv.dataset.pageNum
        continue unless pageNum?
        
        pageCanvas = pageDiv.querySelector('canvas')
        continue unless pageCanvas?
        
        # 重新渲染这一页
        refreshSinglePreviewPage(pageNum, pageCanvas, pageDiv)

# 刷新单个预览页面
refreshSinglePreviewPage = (pageNum, existingCanvas, pageDiv) ->
    return unless state.currentPDF?
    
    state.currentPDF.getPage(pageNum).then (page) ->
        scale = 1.5  # 预览质量
        viewport = page.getViewport({ scale: scale })
        
        # 使用现有canvas
        existingCanvas.width = viewport.width
        existingCanvas.height = viewport.height
        context = existingCanvas.getContext '2d'
        
        renderContext = 
            canvasContext: context
            viewport: viewport
        
        page.render(renderContext).promise.then ->
            # 重新应用水印
            if watermarkType == 'text' and input.text.value
                drawTextWatermarkOnCanvas existingCanvas, context
            else if watermarkType == 'image' and watermarkImageFile?
                drawImageWatermarkOnCanvas existingCanvas, context
        .catch (error) ->
            console.error "刷新第#{pageNum}页预览失败:", error
    .catch (error) ->
        console.error "获取第#{pageNum}页失败:", error

drawText = ->
    if canvas?
        if textCtx? and typeof redraw == 'function'
            redraw()
            drawTextWatermarkOnCanvas canvas, textCtx
        else
            drawTextWatermarkOnCanvas canvas, canvas.getContext('2d')
    
    # 如果有多页预览正在显示，也更新预览
    refreshMultiPagePreview()

drawTextWatermarkOnCanvas = (targetCanvas, ctx) ->
    return if not input.text.value
    
    textSize = input.size.value * Math.max 15, (Math.min targetCanvas.width, targetCanvas.height) / 25
    
    ctx.save()
    ctx.translate(targetCanvas.width / 2, targetCanvas.height / 2)
    ctx.rotate (input.angle.value) * Math.PI / 180

    ctx.fillStyle = makeStyle()
    ctx.font = 'bold ' + textSize + 'px ' + getFontFamily()
    
    # 处理换行文字
    textLines = input.text.value.split(/\n|\\n/)
    lineHeight = textSize * 1.2
    
    # 计算最大文字宽度
    maxWidth = 0
    for line in textLines
        width = ctx.measureText(line).width
        maxWidth = Math.max maxWidth, width
    
    # 计算总文字高度
    totalHeight = textLines.length * lineHeight
    
    step = Math.sqrt (Math.pow targetCanvas.width, 2) + (Math.pow targetCanvas.height, 2)
    margin = (ctx.measureText '啊').width
    
    x = Math.ceil step / (maxWidth + margin)
    y = Math.ceil (step / (input.space.value * totalHeight)) / 2
    
    for i in [-x..x]
        for j in [-y..y]
            # 绘制多行文字
            for lineIndex, line of textLines
                lineY = (input.space.value * totalHeight * j) + (lineIndex - (textLines.length - 1) / 2) * lineHeight
                ctx.fillText line, (maxWidth + margin) * i, lineY
    
    ctx.restore()
    textCtx = ctx if targetCanvas == canvas

drawImageWatermark = ->
    if canvas? and watermarkImageFile?
        if textCtx? and typeof redraw == 'function'
            redraw()
            drawImageWatermarkOnCanvas canvas, textCtx
        else
            drawImageWatermarkOnCanvas canvas, canvas.getContext('2d')
    
    # 如果有多页预览正在显示，也更新预览
    refreshMultiPagePreview()

drawImageWatermarkOnCanvas = (targetCanvas, ctx) ->
    return if not watermarkImageFile?
    
    watermarkReader = new FileReader
    watermarkReader.onload = ->
        watermarkImg = new Image
        watermarkImg.onload = ->
            # 设置透明度
            ctx.save()
            ctx.globalAlpha = parseFloat input.alpha.value
            
            # 计算水印大小
            watermarkSize = input.size.value * Math.min(targetCanvas.width, targetCanvas.height) / 8
            ratio = watermarkImg.width / watermarkImg.height
            watermarkWidth = watermarkSize
            watermarkHeight = watermarkSize / ratio
            
            position = input['watermark-position'].value
            
            switch position
                when 'center'
                    x = (targetCanvas.width - watermarkWidth) / 2
                    y = (targetCanvas.height - watermarkHeight) / 2
                    ctx.drawImage watermarkImg, x, y, watermarkWidth, watermarkHeight
                
                when 'top-left'
                    ctx.drawImage watermarkImg, 20, 20, watermarkWidth, watermarkHeight
                
                when 'top-right'
                    ctx.drawImage watermarkImg, targetCanvas.width - watermarkWidth - 20, 20, watermarkWidth, watermarkHeight
                
                when 'bottom-left'
                    ctx.drawImage watermarkImg, 20, targetCanvas.height - watermarkHeight - 20, watermarkWidth, watermarkHeight
                
                when 'bottom-right'
                    ctx.drawImage watermarkImg, targetCanvas.width - watermarkWidth - 20, targetCanvas.height - watermarkHeight - 20, watermarkWidth, watermarkHeight
                
                when 'repeat'
                    # 平铺水印
                    ctx.translate(targetCanvas.width / 2, targetCanvas.height / 2)
                    ctx.rotate (input.angle.value) * Math.PI / 180
                    
                    cols = Math.ceil(targetCanvas.width / (watermarkWidth * input.space.value))
                    rows = Math.ceil(targetCanvas.height / (watermarkHeight * input.space.value))
                    
                    for i in [-cols..cols]
                        for j in [-rows..rows]
                            x = i * watermarkWidth * input.space.value
                            y = j * watermarkHeight * input.space.value
                            ctx.drawImage watermarkImg, x - watermarkWidth/2, y - watermarkHeight/2, watermarkWidth, watermarkHeight
            
            ctx.restore()
            textCtx = ctx if targetCanvas == canvas
        
        watermarkImg.onerror = ->
            console.error '水印图片加载失败'
        
        watermarkImg.src = watermarkReader.result
    
    watermarkReader.onerror = ->
        console.error '水印图片文件读取失败'
    
    watermarkReader.readAsDataURL watermarkImageFile


# 文件选择事件
image.addEventListener 'change', ->
    file = @files[0]
    
    # 移动端显示加载提示
    if isMobile() and file
        if file.type.includes('pdf')
            showMobileLoadingTip('正在处理PDF文件...')
        else
            showMobileLoadingTip('正在处理图片文件...')
    
    # 支持更多图片格式和PDF
    supportedTypes = [
        'image/png', 'image/jpeg', 'image/gif', 'image/webp', 
        'image/bmp', 'image/svg+xml', 'application/pdf'
    ]
    
    if file.type not in supportedTypes
        hideMobileLoadingTip() if isMobile()
        alert '仅支持图片文件 (PNG, JPG, GIF, WebP, BMP, SVG) 和 PDF 文件'
        return
    
    # 隐藏PDF页面容器
    pdfPagesContainer.style.display = 'none'
    selectedPages.clear()
    graph.innerHTML = ''
    
    readFile()

# 水印类型切换
textWatermarkRadio.addEventListener 'change', ->
    if @checked
        
        watermarkType = 'text'
        textWatermarkOptions.style.display = 'block'
        imageWatermarkOptions.style.display = 'none'
        
        isPDF = originalFileType == 'application/pdf'
        
        # 只有在单页图片模式下才应用水印到画布
        if !isPDF and canvas? and input.text.value and autoRefresh.checked
            
            drawText()
            
        # 对于PDF文件，强制更新预览区域
        if isPDF
            
            isUpdatingPreview = false  # 强制清除标志
            updatePreviewArea()

imageWatermarkRadio.addEventListener 'change', ->
    if @checked
        
        watermarkType = 'image'
        textWatermarkOptions.style.display = 'none'
        imageWatermarkOptions.style.display = 'block'
        
        isPDF = originalFileType == 'application/pdf'
        
        # 只有在单页图片模式下才应用水印到画布
        if !isPDF and canvas? and watermarkImageFile? and autoRefresh.checked
            
            drawImageWatermark()
            
        # 对于PDF文件，强制更新预览区域
        if isPDF
            
            isUpdatingPreview = false  # 强制清除标志
            updatePreviewArea()

# 水印图片选择
watermarkImage.addEventListener 'change', ->
    watermarkImageFile = @files[0]
    imageTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp', 'image/svg+xml']
    
    if watermarkImageFile.type not in imageTypes
        alert '水印仅支持图片格式'
        return
    
    if canvas? and watermarkType == 'image'
        drawImageWatermark() if autoRefresh.checked
        
    # 对于PDF文件，更新预览区域显示图片水印
    if originalFileType == 'application/pdf'
        updatePreviewArea()

# PDF页面选择按钮
selectAllPagesBtn.addEventListener 'click', ->
    pages = pdfPagesDiv.querySelectorAll '.pdf-page'
    for page in pages
        pageNum = parseInt page.dataset.pageNum
        selectedPages.add pageNum
        page.classList.add 'selected'
    updateSelectedPageCount()
    # 自动更新预览区域
    updatePreviewArea()

clearSelectionBtn.addEventListener 'click', ->
    pages = pdfPagesDiv.querySelectorAll '.pdf-page'
    for page in pages
        page.classList.remove 'selected'
    selectedPages.clear()
    updateSelectedPageCount()
    # 自动更新预览区域
    updatePreviewArea()

previewSelectedPagesBtn.addEventListener 'click', ->
  # 刷新预览区域，使用新开发的自动预览功能
  updatePreviewArea()
downloadSelectedPagesBtn.addEventListener 'click', downloadSelectedPages

# 范围输入控件
inputItems.forEach (item) ->
    el = $ '#' + item
    input[item] = el

    # 注意：实时更新范围值显示的事件监听器会在后面的代码中添加

# 自动刷新切换
autoRefresh.addEventListener 'change', ->
    if @checked
        refresh.setAttribute 'disabled', 'disabled'
    else
        refresh.removeAttribute 'disabled'

# 输入变化事件
inputItems.forEach (item) ->
    el = $ '#' + item
    
    # 将范围值显示更新添加到每个滑块
    if el.type == 'range'
        el.addEventListener 'input', updateRangeValues
    
    # 对于任何参数调整，直接更新所有内容
    updatePreviewOnChange = ->
        
        
        # 标记当前是PDF文件
        isPDF = originalFileType == 'application/pdf'
        
        
        # 只有在单页图片模式下才应用水印到画布
        if !isPDF and autoRefresh.checked
            if watermarkType == 'text'
                
                drawText()
            else if watermarkImageFile?
                
                drawImageWatermark()
        
        # 对于PDF文件，直接强制更新预览区域
        if isPDF
            
            
            # 强制清除更新标志，确保能够重新触发更新
            isUpdatingPreview = false
            
            # 强制触发预览更新
            clearTimeout(updateTimeout) if updateTimeout
            updateTimeout = setTimeout(->
                updatePreviewArea()
            , 50)
        else
            
    
    # 为range和color元素使用input事件（实时更新）
    # 为其他元素使用change事件
    if el.type in ['range', 'color']
        el.addEventListener 'input', updatePreviewOnChange
    else
        el.addEventListener 'change', updatePreviewOnChange

# 文字区域支持换行
($ '#text').addEventListener 'keydown', (e) ->
    if e.key == 'Enter' and not e.shiftKey
        # 允许回车换行
        return true

# 手动刷新按钮
refresh.addEventListener 'click', ->
    
    isPDF = originalFileType == 'application/pdf'
    
    # 只有在单页图片模式下才应用水印到画布
    if !isPDF
        if watermarkType == 'text'
            
            drawText()
        else if watermarkImageFile?
            
            drawImageWatermark()
    
    # 对于PDF文件，强制刷新预览区域
    if isPDF
        
        
        # 强制清除更新标志，确保能够重新触发更新
        isUpdatingPreview = false
        
        # 立即触发预览更新
        updatePreviewArea()

# 拖拽上传支持
fileUploadLabel = $ '.file-upload-label'
fileUploadLabel.addEventListener 'dragover', (e) ->
    e.preventDefault()
    @style.borderColor = '#764ba2'
    @style.background = 'rgba(102, 126, 234, 0.15)'

fileUploadLabel.addEventListener 'dragleave', (e) ->
    e.preventDefault()
    @style.borderColor = '#667eea'
    @style.background = 'rgba(102, 126, 234, 0.05)'

fileUploadLabel.addEventListener 'drop', (e) ->
    e.preventDefault()
    @style.borderColor = '#667eea'
    @style.background = 'rgba(102, 126, 234, 0.05)'
    
    files = e.dataTransfer.files
    if files.length > 0
        image.files = files
        image.dispatchEvent new Event('change')

# 初始化范围值显示
updateRangeValues()

# 初始化预览区域，显示操作指引
initializePreviewArea = ->
    graph.innerHTML = '<div class="preview-container"></div>'
    previewContainer = graph.querySelector('.preview-container')
    
    welcomeMessage = document.createElement 'div'
    welcomeMessage.className = 'welcome-message'
    welcomeMessage.innerHTML = """
        <div class="welcome-icon"><i class="fas fa-file-upload"></i></div>
        <h3>欢迎使用图片水印工具</h3>
        <p>请上传图片或PDF文件，然后选择水印类型（文本或图片）</p>
        <p>对于PDF文件，您可以：</p>
        <ul>
            <li>在左侧选择需要添加水印的页面</li>
            <li>在本区域查看预览效果</li>
            <li>调整水印的样式、位置和透明度</li>
            <li>下载添加了水印的文件</li>
        </ul>
    """
    previewContainer.appendChild welcomeMessage

# 页面加载完成后初始化预览区域
initializePreviewArea()

# ==================== 移动端优化 ====================

# 检测是否为移动设备
isMobile = -> 
    /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) or window.innerWidth <= 768

# 移动端触摸优化
if isMobile()
    # 禁用双击缩放（在某些输入元素上）
    document.addEventListener 'touchstart', (e) ->
        if e.touches.length > 1
            e.preventDefault()
    , { passive: false }
    
    # 优化文件选择体验
    fileInput = $ '#image'
    if fileInput
        fileInput.addEventListener 'click', ->
            # 在移动端点击文件输入时，确保能正确触发文件选择
            this.value = ''
    
    # 优化滑块在移动端的体验
    rangeInputs = document.querySelectorAll '.range-control'
    rangeInputs.forEach (input) ->
        input.addEventListener 'touchstart', (e) ->
            # 防止页面滚动
            e.stopPropagation()
        , { passive: true }
    
    # 改善PDF页面选择在移动端的体验
    pdfPagesContainer?.addEventListener 'touchstart', (e) ->
        # 防止触摸时的意外滚动
        if e.target.closest('.pdf-page')
            e.stopPropagation()
    , { passive: true }

# 屏幕方向改变时重新布局
window.addEventListener 'orientationchange', ->
    setTimeout ->
        # 强制重新计算布局
        if canvas and canvas.style
            canvas.style.maxWidth = '100%'
            canvas.style.height = 'auto'
        
        # 重新渲染预览（如果存在）
        if state.currentPDF and selectedPages.size > 0
            updatePreviewArea()
    , 100

# 移动端键盘优化
if isMobile()
    # 当虚拟键盘弹出时，调整视图
    textInput = $ '#text'
    if textInput
        textInput.addEventListener 'focus', ->
            # 滚动到输入框位置
            setTimeout ->
                this.scrollIntoView({ behavior: 'smooth', block: 'center' })
            , 300
        
        textInput.addEventListener 'blur', ->
            # 键盘收起后，滚动回顶部
            setTimeout ->
                window.scrollTo({ top: 0, behavior: 'smooth' })
            , 100

# 添加加载状态提示（移动端网络可能较慢）
showMobileLoadingTip = (message) ->
    if isMobile()
        tip = document.createElement 'div'
        tip.className = 'mobile-loading-tip'
        tip.innerHTML = """
            <div style="
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                background: rgba(0, 0, 0, 0.8);
                color: white;
                padding: 15px 20px;
                border-radius: 10px;
                font-size: 14px;
                z-index: 10000;
                text-align: center;
            ">
                <i class="fas fa-spinner fa-spin" style="margin-right: 8px;"></i>
                #{message}
            </div>
        """
        document.body.appendChild tip
        tip

hideMobileLoadingTip = ->
    tip = document.querySelector '.mobile-loading-tip'
    tip?.remove()

# 覆盖原有的文件处理函数，添加移动端加载提示
# 注意：不能直接覆盖 addEventListener，需要修改原始事件处理器
