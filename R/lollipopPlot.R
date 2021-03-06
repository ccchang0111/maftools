#' Draws lollipop plot of amino acid changes on to Protein structure.
#'
#' @description Draws lollipop plot of amino acid changes.
#' @details This function by default looks for fields 'HGVSp_Short', 'AAChange' or 'Protein_Change' in maf file. One can also manually specify field name containing amino acid changes.
#' @param maf an \code{\link{MAF}} object generated by \code{\link{read.maf}}
#' @param gene HGNC symbol for which protein structure to be drawn.
#' @param AACol manually specify column name for amino acid changes. Default looks for fields 'HGVSp_Short', 'AAChange' or 'Protein_Change'. Changes can be of any format i.e, can be a numeric value or HGVSp annotations (e.g; p.P459L, p.L2195Pfs*30 or p.Leu2195ProfsTer30)
#' @param labelPos Amino acid positions to label. If 'all', labels all variants.
#' @param labPosSize Text size for labels. Default 3
#' @param showMutationRate Default TRUE
#' @param fn basename for plot file to be saved. If provided a pdf will be generated. Default NULL.
#' @param showDomainLabel Label domains within the plot. Default TRUE. If FALSE they will be annotated in legend.
#' @param cBioPortal Adds annotations similar to cBioPortals MutationMapper and collapse Variants into Truncating and rest.
#' @param refSeqID RefSeq transcript identifier for \code{gene} if known.
#' @param proteinID RefSeq protein identifier for \code{gene} if known.
#' @param repel If points are too close to each other, use this option to repel them. Default FALSE. Warning: naive method, might make plot ugly in case of too many variants!
#' @param collapsePosLabel Collapses overlapping labels at same position. Default TRUE
#' @param legendTxtSize Text size for legend. Default 10
#' @param labPosAngle angle for labels. Defaults to horizonal 0 degree labels. Set to 90 for vertical; 45 for diagonal labels.
#' @param domainLabelSize text size for domain labels. Default 2.
#' @param printCount If TRUE, prints number of summarized variants for the given protein.
#' @param colors named vector of colors for each Variant_Classification. Default NULL.
#' @param domainColors Manual colors for protein domains
#' @param labelOnlyUniqueDoamins Default TRUE only labels unique doamins.
#' @param defaultYaxis If FALSE, just labels min and maximum y values on y axis.
#' @param pointSize size of lollipop heads. Default 1.5
#' @param titleSize font size for title and subtitle. Default c(12, 10)
#' @return ggplot object of the plot, which can be futher modified.
#' @import ggrepel
#' @examples
#' laml.maf <- system.file("extdata", "tcga_laml.maf.gz", package = "maftools")
#' laml <- read.maf(maf = laml.maf)
#' lollipopPlot(maf = laml, gene = 'KIT', AACol = 'Protein_Change')
#'
#' @export

lollipopPlot = function(maf, gene = NULL, AACol = NULL, labelPos = NULL, labPosSize = 3, showMutationRate = TRUE, fn = NULL,
                         showDomainLabel = TRUE, cBioPortal = FALSE, refSeqID = NULL, proteinID = NULL,
                         repel = FALSE, collapsePosLabel = TRUE, legendTxtSize = 10, labPosAngle = 0, domainLabelSize = 2.5,
                         printCount = FALSE, colors = NULL, domainColors = NULL, labelOnlyUniqueDoamins = TRUE, defaultYaxis = TRUE, titleSize = c(12, 10), pointSize = 1.5){

  if(is.null(gene)){
    stop('Please provide a gene name.')
  }

  geneID = gene
  #Protein domain source.
  gff = system.file('extdata', 'protein_domains.txt.gz', package = 'maftools')

  if(Sys.info()[['sysname']] == 'Windows'){
    gff.gz = gzfile(description = gff, open = 'r')
    gff <- suppressWarnings( data.table(read.csv( file = gff.gz, header = TRUE, sep = '\t', stringsAsFactors = FALSE)) )
    close(gff.gz)
  } else{
    gff = data.table::fread(input = paste('zcat <', gff), sep = '\t', stringsAsFactors = FALSE)
  }

  mut = subsetMaf(maf = maf, includeSyn = FALSE, genes = gene, query = "Variant_Type != 'CNV'")

  if(is.null(AACol)){
    pchange = c('HGVSp_Short', 'Protein_Change', 'AAChange')
    if(pchange[pchange %in% colnames(mut)] > 0){
      pchange = suppressWarnings(pchange[pchange %in% colnames(mut)][1])
      message(paste0("Assuming protein change information are stored under column ", pchange,". Use argument AACol to override if necessary."))
      colnames(mut)[which(colnames(mut) == pchange)] = 'AAChange'
    }else{
      message('Available fields:')
      print(colnames(mut))
      stop('AAChange field not found in MAF. Use argument AACol to manually specifiy field name containing protein changes.')
    }
  }else{
    colnames(mut)[which(colnames(mut) == AACol)] = 'AAChange'
  }

  prot.dat = mut[Hugo_Symbol %in% geneID, .(Variant_Type, Variant_Classification, AAChange)]
  if(nrow(prot.dat) == 0){
    stop(paste(geneID, 'does not seem to have any mutations!', sep=' '))
  }

  prot = gff[HGNC %in% geneID]

  if(nrow(prot) == 0){
    stop(paste('Structure for protein', geneID, 'not found.', sep=' '))
  }

  if(!is.null(refSeqID)){
    prot = gff[refseq.ID == refSeqID]
  } else if(!is.null(proteinID)){
    prot = gff[protein.ID == proteinID]
  } else{
    txs = unique(prot$refseq.ID)
    if(length(txs) > 1){
      message(paste(length(txs), ' transcripts available. Use arguments refSeqID or proteinID to manually specify tx name.', sep = ''))
      print(prot[!duplicated(protein.ID),.(HGNC, refseq.ID, protein.ID, aa.length)])
      prot = prot[which(prot$aa.length == max(prot$aa.length)),]
      if(length(unique(prot$refseq.ID)) > 1){
        prot = prot[which(prot$refseq.ID == unique(prot[,refseq.ID])[1]),]
        message(paste('Using longer transcript', unique(prot[,refseq.ID])[1], 'for now.', sep=' '))
      } else{
        message(paste('Using longer transcript', unique(prot[,refseq.ID])[1], 'for now.', sep=' '))
      }
    }
  }

  #Legth of protein
  len = as.numeric(max(prot$aa.length, na.rm = TRUE))
  #Remove NA's
  prot = prot[!is.na(Label)]

  #hard coded colors for variant classification if user doesnt provide any

  sampleSize = as.numeric(maf@summary[ID %in% 'Samples', summary])
  mutRate = round(getGeneSummary(x = maf)[Hugo_Symbol %in% geneID, MutatedSamples]/sampleSize*100, digits = 2)
  cbioSubTitle = paste0(geneID, ": [Somatic Mutation Rate: ", mutRate, "%]")

  if(cBioPortal){
    vc = c("Nonstop_Mutation", "Frame_Shift_Del", "Missense_Mutation",
           "Nonsense_Mutation", "Splice_Site", "Frame_Shift_Ins", "In_Frame_Del", "In_Frame_Ins")
    vc.cbio = c("Truncating", "Truncating", "Missense", "Truncating", "Truncating", "Truncating",
                "In-frame", "In-frame")
    names(vc.cbio) = vc
    col = c('Truncating' = "black", 'Missense' = '#33A02C', 'In-frame' = 'brown')
  }else{
    if(is.null(colors)){
      col = c(RColorBrewer::brewer.pal(12,name = "Paired"), RColorBrewer::brewer.pal(11,name = "Spectral")[1:3],'black')
      names(col) = names = c('Nonstop_Mutation','Frame_Shift_Del','Silent','Missense_Mutation','IGR','Nonsense_Mutation',
                             'RNA','Splice_Site','Intron','Frame_Shift_Ins','In_Frame_Dell','In_Frame_Del','ITD','In_Frame_Ins','Translation_Start_Site',"Multi_Hit")
    }else{
      col = colors
    }
  }

  #prot.dat = prot.dat[Variant_Classification != 'Splice_Site']
  #Remove 'p.'
  prot.spl = strsplit(x = as.character(prot.dat$AAChange), split = '.', fixed = TRUE)
  prot.conv = sapply(sapply(prot.spl, function(x) x[length(x)]), '[', 1)

  prot.dat[,conv := prot.conv]
  #If conversions are in HGVSp_long (default HGVSp) format, we will remove strings Ter followed by anything (e.g; p.Asn1986GlnfsTer13)
  pos = gsub(pattern = 'Ter.*', replacement = '',x = prot.dat$conv)

  #Following parsing takes care of most of HGVSp_short and HGVSp_long format
  pos = gsub(pattern = '[[:alpha:]]', replacement = '', x = pos)
  pos = gsub(pattern = '\\*$', replacement = '', x = pos) #Remove * if nonsense mutation ends with *
  pos = gsub(pattern = '^\\*', replacement = '', x = pos) #Remove * if nonsense mutation starts with *
  pos = gsub(pattern = '\\*.*', replacement = '', x = pos) #Remove * followed by position e.g, p.C229Lfs*18


  #pos = as.numeric(sapply(strsplit(x = pos, split = '_', fixed = TRUE), '[[', 1))
  pos = as.numeric(sapply(X = strsplit(x = pos, split = '_', fixed = TRUE), FUN = function(x) x[1]))
  prot.dat[,pos := abs(pos)]

  if(nrow( prot.dat[is.na(pos)]) > 0){
    message(paste('Removed', nrow( prot.dat[is.na(prot.dat$pos),]), 'mutations for which AA position was not available', sep = ' '))
    #print(prot.dat[is.na(pos)])
    prot.dat = prot.dat[!is.na(pos)]
  }

  prot.snp.sumamry = prot.dat[,.N, .(Variant_Classification, conv, pos)]
  colnames(prot.snp.sumamry)[ncol(prot.snp.sumamry)] = 'count'
  maxCount = max(prot.snp.sumamry$count, na.rm = TRUE)

  prot.snp.sumamry = prot.snp.sumamry[order(prot.snp.sumamry$pos),]
  #prot.snp.sumamry$distance = c(0,diff(prot.snp.sumamry$pos))

  if(cBioPortal){
    prot.snp.sumamry$Variant_Classification = vc.cbio[as.character(prot.snp.sumamry$Variant_Classification)]
  }

  if(maxCount <= 5){
    prot.snp.sumamry$count2 = 1+prot.snp.sumamry$count
    lim.pos = 2:6
    lim.lab = 1:5
  }else{
    prot.snp.sumamry$count2 = 1+(prot.snp.sumamry$count * (5/max(prot.snp.sumamry$count)))
    lim.pos = prot.snp.sumamry[!duplicated(count2), count2]
    lim.lab = prot.snp.sumamry[!duplicated(count2), count]
  }

  if(length(lim.pos) > 6){
    lim.dat = data.table::data.table(pos = lim.pos, lab = lim.lab)
    lim.dat[,posRounded := round(pos)]
    lim.dat = lim.dat[!duplicated(posRounded)]
    lim.pos = lim.dat[,pos]
    lim.lab = lim.dat[,lab]
  }

  if(!defaultYaxis){
    lim.pos = c(min(lim.pos), max(lim.pos))
    lim.lab = c(min(lim.lab), max(lim.lab))
  }

  clusterSize = 10 #Change this later as an argument to user.
  if(repel){
    prot.snp.sumamry = repelPoints(dat = prot.snp.sumamry, protLen = len, clustSize = clusterSize)
  }else{
    prot.snp.sumamry$pos2 = prot.snp.sumamry$pos
  }

  xlimPos = pretty(0:max(prot$aa.length))
  xlimPos[length(xlimPos)] = max(prot$aa.length)+3

  if(xlimPos[length(xlimPos)] - xlimPos[length(xlimPos)-1] <= 10){
    xlimPos = xlimPos[-(length(xlimPos)-1)]
  }

  pl = ggplot()+geom_segment(data = prot.snp.sumamry, aes(x = pos, xend = pos2, y = 0.8, yend = count2-0.03), color = 'gray70', size = 0.5)
  pl = pl+geom_point(data = prot.snp.sumamry, aes(x = pos2, y = count2, color = Variant_Classification), size = pointSize, alpha = 0.7)
  pl = pl+scale_color_manual(values = col)+xlab('')+ylab('# Mutations')
  pl = pl+geom_segment(aes_all(c('x','y', 'xend', 'yend')), data = data.frame(y = c(min(lim.pos), 0), yend = c(6, 0), x = c(0, 0), xend = c(0, max(xlimPos))), size = 0.7)
  pl = pl+theme(panel.background = element_blank(), axis.text.y = element_text(face="bold", size = 12), axis.text.x = element_text(face="bold", size = 9))
  pl = pl+scale_y_continuous(breaks = lim.pos, labels = lim.lab, expand = c(0, 0), limits = c(0, 6.5))
  pl = pl+scale_x_continuous(breaks = xlimPos, expand = c(0, 0), limits = c(0, max(xlimPos)+round(0.02*max(xlimPos))))
  pl = pl+theme(legend.position = 'bottom', legend.text=element_text(size = legendTxtSize), legend.title = element_blank(), legend.key.size =  unit(0.35, "cm"), legend.box.background = element_blank())
  pl = pl+guides(colour = guide_legend(nrow = 3, override.aes = list(size = 3, fill = NA)), fill = guide_legend(nrow = 3, override.aes = list(size = 3)))
  #pl = pl+theme(axis.text.y = element_blank(), axis.line.x = element_blank(), axis.ticks.y = element_blank())
  #pl = pl+geom_segment(aes_all(c('y', 'yend')), data = data.frame(y = c(min(lim.pos), 0), yend = c(6, 0), x = c(0, 0), xend = c(0, len)))

  # p = ggplot()+geom_segment(data = prot.snp.sumamry, aes(x = pos, xend = pos2, y = 0.8, yend = count2-0.03), color = 'gray70', size = 0.5)+
  #   geom_point(data = prot.snp.sumamry, aes(x = pos2, y = count2, color = Variant_Classification), size = 1.5, alpha = 0.7)+
  #   scale_color_manual(values = col)+cowplot::theme_cowplot()+
  #   theme(legend.text=element_text(size = legendTxtSize), axis.text.y = element_text(size = 8), legend.position = 'bottom', axis.line.x = element_blank(), legend.title = element_blank(), legend.key.size =  unit(0.35, "cm"))+
  #   xlab('')+ylab('# Mutations')+
  #   guides(colour = guide_legend(nrow = 3, override.aes = list(size = 3)), fill = guide_legend(nrow = 3, override.aes = list(size = 3)))+
  #   scale_x_continuous(breaks = pretty(0:max(prot$aa.length)))+
  #   scale_y_continuous(breaks = lim.pos, labels = lim.lab, limits = c(0, 6.5))

  p = pl+geom_rect(data = prot, aes(xmin = 0, xmax = len, ymin = 0.2, ymax = 0.8), fill = 'gray')

  #Plot protein domains. If no domains found, just draw background protein.
  if(nrow(prot) > 0){
    if(showDomainLabel){
      p = p+geom_rect(data = prot, aes(xmin = Start, xmax = End, ymin = 0.1, ymax = 0.9, fill = Label))
      if(labelOnlyUniqueDoamins){
        protLab = prot[!duplicated(Label)]
        protLab$pos = rowMeans(x = protLab[,.(Start, End)])
        p = p+geom_text(data = protLab, aes(x = pos, y = 0.5, label = Label, fontface = 'bold'), size = domainLabelSize)+guides(fill = FALSE)
      }else{
        prot$pos = rowMeans(x = prot[,.(Start, End)])
        p = p+geom_text(data = prot, aes(x = pos, y = 0.5, label = Label, fontface = 'bold'), size = domainLabelSize)+guides(fill = FALSE)
      }
    }else{
      p = p+geom_rect(data = prot, aes(xmin = Start, xmax = End, ymin = 0.1, ymax = 0.9, fill = Label))
    }
    if(!is.null(domainColors)){
      p = p+scale_fill_manual(values = domainColors)
    }
  }

  #If user asks to label points, use ggrepel to label.
  if(!is.null(labelPos)){
    prot.snp.sumamry = data.table::data.table(prot.snp.sumamry)

    if(length(labelPos) == 1){
      if(labelPos != 'all'){
        prot.snp.sumamry$labThis = ifelse(test = prot.snp.sumamry$pos %in% labelPos, yes = 'yes', no = 'no')
        labDat = prot.snp.sumamry[labThis %in% 'yes']
      }else{
        labDat = prot.snp.sumamry
      }
    }else{
      prot.snp.sumamry$labThis = ifelse(test = prot.snp.sumamry$pos %in% labelPos, yes = 'yes', no = 'no')
      labDat = prot.snp.sumamry[labThis %in% 'yes']
    }

    if(nrow(labDat) == 0){
      message(paste0("Position ",labelPos, " doesn't seem to be mutated. Here are the mutated foci."))
      return(prot.snp.sumamry[,.(mutations = sum(count)), pos][order(mutations, decreasing = TRUE)])
    }


    if(collapsePosLabel){
      uniquePos = unique(labDat[,pos2])
      labDatCollapsed = data.table::data.table()
      for(i in 1:length(uniquePos)){
        uniqueDat = labDat[pos2 %in% uniquePos[i]]
        if(nrow(uniqueDat) > 1){
          maxDat = max(uniqueDat[,count2])
          maxPos = unique(uniqueDat[,pos2])
          toLabel = uniqueDat[,conv]
          toLabel = paste(toLabel[1],paste(gsub(pattern = '^[A-z]*[[:digit:]]*', replacement = '', x = toLabel[2:length(toLabel)]), collapse = '/'), sep = '/')
          labDatCollapsed = rbind(labDatCollapsed, data.table::data.table(pos2 = maxPos, count2 = maxDat, conv = toLabel))
        }else{
          labDatCollapsed = rbind(labDatCollapsed, data.table::data.table(pos2 = uniqueDat[,pos2], count2 = uniqueDat[,count2], conv = uniqueDat[,conv]))
        }
      }
      labDat = labDatCollapsed
    }

    if(length(labelPos) == 1){
      if(labelPos == 'all'){
        p = p+ggrepel::geom_text_repel(data = labDat, aes(pos2, count2, label = as.character(conv), fontface = 'bold'), force = 2, nudge_y = 0.3, nudge_x = 0.3, size = labPosSize, segment.alpha = 0.6, min.segment.length = unit(0.7, "cm"), angle = labPosAngle)
      }else{
        p = p+ggrepel::geom_text_repel(data = labDat, aes(pos2, count2, label = as.character(conv), fontface = 'bold'), force = 2, nudge_y = 0.3, nudge_x = 0.3, size = labPosSize, segment.alpha = 0.6, min.segment.length = unit(0.7, "cm"), angle = labPosAngle)
        #p = p+geom_text_repel(data = prot.snp.summary[labThis %in% 'yes'], aes(pos2, count2, label = as.character(conv)), force = 2, nudge_y = 0.6, nudge_x = 0.3)
      }
    } else{
      #prot.snp.sumamry$labThis = ifelse(test = prot.snp.sumamry$pos %in% labelPos, yes = 'yes', no = 'no')
      p = p+ggrepel::geom_text_repel(data = labDat, aes(pos2, count2, label = as.character(conv), fontface = 'bold'), force = 2, nudge_y = 0.5, nudge_x = 0.3, size = labPosSize, segment.alpha = 0.6, min.segment.length = unit(0.7, "cm"), angle = labPosAngle)
      #p = p+geom_text_repel(data = prot.snp.summary[labThis %in% 'yes'], aes(pos2, count2, label = as.character(conv)), force = 2, nudge_y = 0.6, nudge_x = 0.3)
    }
  }

  p = p+ggtitle(label = paste(geneID, ' (',unique(prot[,refseq.ID]), ')',sep=''))
  if(showMutationRate){

    p = p+ggtitle(label = cbioSubTitle, subtitle = unique(prot[,refseq.ID]))+
      theme(plot.title = element_text(size = titleSize[1], face = "bold"))+
      theme(plot.subtitle = element_text(size = titleSize[2], face = "bold"))
  }

  if(cBioPortal){
    p = p+ggtitle(label = cbioSubTitle, subtitle = paste0(geneID, ': ' ,unique(prot[,refseq.ID])))+theme(plot.title = element_text(size = 10, face = "bold", color = 'blue', hjust = 0))+
      theme(plot.subtitle = element_text(size = 7, face = "bold", color = '#1F78B4'))
  }

  print(p)

  if(printCount){
    print(prot.snp.sumamry[,.(mutations = sum(count)), pos][order(mutations, decreasing = TRUE)])
  }

  if(!is.null(fn)){
    cowplot::save_plot(filename = paste0(fn, ".pdf"), plot = p, base_height = 4, base_width = 8, bg = 'white')
  }

  return(p)
}
